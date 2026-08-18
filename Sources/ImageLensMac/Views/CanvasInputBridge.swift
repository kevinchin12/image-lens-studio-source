import AppKit
import ImageLensCanvas
import SwiftUI

/// A narrow AppKit edge for canvas input that SwiftUI gestures do not model
/// well: scroll-wheel panning, trackpad magnification, and a temporary
/// spacebar pan tool.
///
/// The bridge owns only the lifetime of the current input sequence. The
/// viewport remains owned by `WorkspaceSession` through `onPan` and `onZoom`.
struct CanvasInputBridge: NSViewRepresentable {
    let resizeCursorRegions: [CanvasResizeCursorRegion]
    let horizontalScrollRegions: [CGRect]
    let activeResizeEdge: CanvasNodeResizeEdge?
    let onPan: (CGSize) -> Void
    let onZoom: (Double, CGPoint) -> Void
    let onDeleteSelection: () -> Void
    let onSelectAll: () -> Void
    let onCopySelection: () -> Void
    let onPaste: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCancelInteraction: () -> Void
    let onPanInteractionChanged: (Bool) -> Void
    let onZoomInteractionChanged: (Bool) -> Void

    func makeNSView(context: Context) -> CanvasInputMonitorView {
        let view = CanvasInputMonitorView()
        view.resizeCursorRegions = resizeCursorRegions
        view.horizontalScrollRegions = horizontalScrollRegions
        view.activeResizeEdge = activeResizeEdge
        view.onPan = onPan
        view.onZoom = onZoom
        view.onDeleteSelection = onDeleteSelection
        view.onSelectAll = onSelectAll
        view.onCopySelection = onCopySelection
        view.onPaste = onPaste
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onCancelInteraction = onCancelInteraction
        view.onPanInteractionChanged = onPanInteractionChanged
        view.onZoomInteractionChanged = onZoomInteractionChanged
        return view
    }

    func updateNSView(_ nsView: CanvasInputMonitorView, context: Context) {
        nsView.resizeCursorRegions = resizeCursorRegions
        nsView.horizontalScrollRegions = horizontalScrollRegions
        nsView.activeResizeEdge = activeResizeEdge
        nsView.onPan = onPan
        nsView.onZoom = onZoom
        nsView.onDeleteSelection = onDeleteSelection
        nsView.onSelectAll = onSelectAll
        nsView.onCopySelection = onCopySelection
        nsView.onPaste = onPaste
        nsView.onUndo = onUndo
        nsView.onRedo = onRedo
        nsView.onCancelInteraction = onCancelInteraction
        nsView.onPanInteractionChanged = onPanInteractionChanged
        nsView.onZoomInteractionChanged = onZoomInteractionChanged
    }

    static func dismantleNSView(_ nsView: CanvasInputMonitorView, coordinator: Void) {
        nsView.stopMonitoring()
    }
}

final class CanvasInputMonitorView: NSView {
    var horizontalScrollRegions: [CGRect] = []
    var resizeCursorRegions: [CanvasResizeCursorRegion] = [] {
        didSet {
            guard oldValue != resizeCursorRegions else { return }
            refreshCursor()
        }
    }
    var activeResizeEdge: CanvasNodeResizeEdge? {
        didSet {
            guard oldValue != activeResizeEdge else { return }
            refreshCursor()
        }
    }
    var onPan: ((CGSize) -> Void)?
    var onZoom: ((Double, CGPoint) -> Void)?
    var onDeleteSelection: (() -> Void)?
    var onSelectAll: (() -> Void)?
    var onCopySelection: (() -> Void)?
    var onPaste: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCancelInteraction: (() -> Void)?
    var onPanInteractionChanged: ((Bool) -> Void)?
    var onZoomInteractionChanged: ((Bool) -> Void)?

    private var eventMonitor: Any?
    private var monitoredWindow: NSWindow?
    private var isSpacePanToolActive = false
    private var isDraggingCanvas = false
    private var canvasDragButtonNumber: Int?
    private var lastDragLocation: CGPoint?
    private var lastReportedPanInteractionState = false
    private var isMagnifyingCanvas = false
    private var magnificationAnchor: CGPoint?
    private var consumedKeyCodes: Set<UInt16> = []
    private var isCanvasCommandScopeActive = false
    private var scrollOwner: ScrollOwner?

    private enum ScrollOwner {
        case canvas
        case horizontalShelf
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Menu key equivalents are evaluated before this responder receives the
    /// event. Anything that reaches the canvas without a matching action is a
    /// harmless unsupported key, so do not call `super` and trigger NSBeep.
    override func keyDown(with event: NSEvent) {}

    override func keyUp(with event: NSEvent) {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window !== monitoredWindow else { return }
        stopMonitoring()
        guard window != nil else { return }
        startMonitoring()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let cursor = panCursorIntent.nsCursor {
            addCursorRect(bounds, cursor: cursor)
            return
        }
        if let activeResizeEdge {
            addCursorRect(bounds, cursor: activeResizeEdge.nsCursor)
            return
        }
        for region in resizeCursorRegions {
            let visibleRect = region.rect.intersection(bounds)
            guard !visibleRect.isNull, !visibleRect.isEmpty else { continue }
            addCursorRect(visibleRect, cursor: region.edge.nsCursor)
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let monitoredWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: monitoredWindow
            )
        }
        monitoredWindow = nil
        isCanvasCommandScopeActive = false
        resetPanInteraction(restoreArrowCursor: false)
        resetMagnification()
    }

    private func startMonitoring() {
        guard let window else { return }
        monitoredWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )

        let mask: NSEvent.EventTypeMask = [
            .scrollWheel,
            .magnify,
            .keyDown,
            .keyUp,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .otherMouseDown,
            .otherMouseDragged,
            .otherMouseUp,
            .cursorUpdate
        ]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            // `handle` deliberately returns nil for consumed events. Optional
            // chaining followed by `?? event` would resurrect that event and
            // send it into NSWindow's empty responder chain, producing NSBeep
            // even though the canvas action already ran.
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === monitoredWindow else { return event }

        switch event.type {
        case .scrollWheel:
            guard !isDraggingCanvas else { return nil }
            guard !isMagnifyingCanvas else { return nil }
            // A text field elsewhere in the window may remain first responder
            // after the pointer returns to the canvas. Scroll ownership follows
            // the pointer, not that stale responder, so trackpad panning remains
            // available after editing prompts or selecting summary text.
            guard containsCurrentPointer else { return event }
            let navigationModifiers = event.modifierFlags.intersection([
                .command,
                .control,
                .option,
                .shift
            ])
            if navigationModifiers == [.command] {
                guard let factor = CanvasScrollZoomPolicy.factor(
                    deltaY: Double(event.scrollingDeltaY),
                    isPrecise: event.hasPreciseScrollingDeltas
                ) else { return nil }
                scrollOwner = nil
                onZoom?(factor, localLocation(of: event))
                return nil
            }
            let owner = scrollOwnerForCurrentSequence(event)
            defer { finishScrollSequenceIfNeeded(event) }
            if owner == .horizontalShelf { return event }
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            let translation = CGSize(
                width: event.scrollingDeltaX * multiplier,
                height: event.scrollingDeltaY * multiplier
            )
            guard translation != .zero else { return event }
            onPan?(translation)
            return nil

        case .magnify:
            return handleMagnification(event)

        case .keyDown:
            if activeTextResponderRole == .editable { return event }
            if activeTextResponderRole == .selectable {
                return isSelectableTextCommand(event)
                    || shouldPreserveNativeNavigationKey(event)
                    ? event
                    : consumeKeyDown(event)
            }
            // SwiftUI sidebar rows do not always become AppKit first responder,
            // so command ownership also follows the last explicit mouse-down
            // surface. This prevents a stale canvas responder from mutating the
            // previous selection while the user is operating the sidebar.
            if !keyboardRoutingContext.windowOwnsCanvasCommands {
                if let offCanvasAction = supportedKeyAction(for: event) {
                    switch offCanvasAction {
                    case .spacePan where containsCurrentPointer:
                        isCanvasCommandScopeActive = true
                        monitoredWindow?.makeFirstResponder(self)
                    case .spacePan, .cancel:
                        return event
                    case .deleteSelection, .selectAll, .copySelection, .paste, .undo, .redo:
                        // These are canvas-owned editing commands. When the
                        // sidebar was the last explicit interaction surface,
                        // consume them before a stale canvas responder or the
                        // standard Edit menu can act or beep.
                        return consumeKeyDown(event)
                    }
                } else {
                    if shouldPreserveNativeNavigationKey(event)
                        || hasEnabledMenuKeyEquivalent(for: event)
                        || isExplicitSwiftUIShortcut(event) {
                        return event
                    }
                    // Delete and otherwise unsupported printable keys have no
                    // sidebar action today. Consume them so they neither mutate
                    // the stale canvas selection nor fall through to NSBeep.
                    return consumeKeyDown(event)
                }
            }
            guard let action = supportedKeyAction(for: event) else {
                let commandModifiers = event.modifierFlags.intersection([.command, .control])
                if !commandModifiers.isEmpty {
                    // Never invoke `performKeyEquivalent` speculatively: AppKit
                    // itself beeps when a disabled Edit command is attempted.
                    // Valid app/menu and explicit SwiftUI button shortcuts keep
                    // the normal dispatch path; every unsupported combination
                    // is consumed before it reaches an empty responder chain.
                    if hasEnabledMenuKeyEquivalent(for: event)
                        || isExplicitSwiftUIShortcut(event) {
                        return event
                    }
                    return consumeKeyDown(event)
                }
                // Preserve native focus traversal, activation, scrolling and
                // function keys. Printable keys have no meaning outside the
                // text system in this app and are consumed window-wide.
                return shouldPreserveNativeNavigationKey(event)
                    ? event
                    : consumeKeyDown(event)
            }

            switch action {
            case .cancel:
                onCancelInteraction?()
                return consumeKeyDown(event)
            case .selectAll:
                onSelectAll?()
                return consumeKeyDown(event)
            case .copySelection:
                onCopySelection?()
                return consumeKeyDown(event)
            case .paste:
                onPaste?()
                return consumeKeyDown(event)
            case .undo:
                onUndo?()
                return consumeKeyDown(event)
            case .redo:
                onRedo?()
                return consumeKeyDown(event)
            case .deleteSelection:
                onDeleteSelection?()
                return consumeKeyDown(event)
            case .spacePan:
                guard keyboardRoutingContext.canvasOwnsKeyboardInput
                        || isSpacePanToolActive
                        || containsCurrentPointer else {
                    return consumeKeyDown(event)
                }
                if !isSpacePanToolActive {
                    isSpacePanToolActive = true
                    reportPanInteractionIfNeeded()
                    refreshCursor()
                }
                // Key-repeat events for a held Space belong to the same pan
                // tool activation and must not leak to AppKit's responder.
                return consumeKeyDown(event)
            }

        case .keyUp:
            guard consumedKeyCodes.remove(event.keyCode) != nil else { return event }
            if event.keyCode == 49, isSpacePanToolActive {
                isSpacePanToolActive = false
                reportPanInteractionIfNeeded()
                refreshCursor()
            }
            return nil

        case .leftMouseDown:
            let activatesCanvasCommands = containsEventLocation(event)
                && !isTextInput(at: event.locationInWindow)
            isCanvasCommandScopeActive = activatesCanvasCommands
            if activatesCanvasCommands {
                monitoredWindow?.makeFirstResponder(self)
            }
            guard isSpacePanToolActive,
                  !isDraggingCanvas,
                  containsEventLocation(event) else { return event }
            resetMagnification()
            isDraggingCanvas = true
            canvasDragButtonNumber = 0
            lastDragLocation = localLocation(of: event)
            reportPanInteractionIfNeeded()
            refreshCursor()
            return nil

        case .leftMouseDragged:
            guard isDraggingCanvas,
                  canvasDragButtonNumber == 0,
                  let lastDragLocation else { return event }
            let location = localLocation(of: event)
            let translation = CGSize(
                width: location.x - lastDragLocation.x,
                height: location.y - lastDragLocation.y
            )
            self.lastDragLocation = location
            if translation != .zero {
                onPan?(translation)
            }
            NSCursor.closedHand.set()
            return nil

        case .leftMouseUp:
            guard isDraggingCanvas, canvasDragButtonNumber == 0 else { return event }
            isDraggingCanvas = false
            canvasDragButtonNumber = nil
            lastDragLocation = nil
            reportPanInteractionIfNeeded()
            refreshCursor()
            return nil

        case .otherMouseDown:
            guard event.buttonNumber == 2,
                  !isDraggingCanvas,
                  NSEvent.pressedMouseButtons & 1 == 0,
                  containsEventLocation(event) else { return event }
            resetMagnification()
            isDraggingCanvas = true
            canvasDragButtonNumber = 2
            lastDragLocation = localLocation(of: event)
            reportPanInteractionIfNeeded()
            refreshCursor()
            NSCursor.closedHand.set()
            return nil

        case .otherMouseDragged:
            guard event.buttonNumber == 2,
                  isDraggingCanvas,
                  canvasDragButtonNumber == 2,
                  let lastDragLocation else { return event }
            let location = localLocation(of: event)
            let translation = CGSize(
                width: location.x - lastDragLocation.x,
                height: location.y - lastDragLocation.y
            )
            self.lastDragLocation = location
            if translation != .zero {
                onPan?(translation)
            }
            NSCursor.closedHand.set()
            return nil

        case .otherMouseUp:
            guard event.buttonNumber == 2,
                  isDraggingCanvas,
                  canvasDragButtonNumber == 2 else { return event }
            isDraggingCanvas = false
            canvasDragButtonNumber = nil
            lastDragLocation = nil
            reportPanInteractionIfNeeded()
            refreshCursor()
            return nil

        case .cursorUpdate:
            guard containsCurrentPointer else { return event }
            if let cursor = resolvedCursor(at: localLocation(of: event)) {
                cursor.set()
                return nil
            }
            return event

        default:
            return event
        }
    }

    private func scrollOwnerForCurrentSequence(_ event: NSEvent) -> ScrollOwner {
        if let scrollOwner {
            let beginsNewSequence = event.phase.contains(.began)
                || (event.phase.isEmpty && event.momentumPhase.isEmpty)
            if scrollOwner == .horizontalShelf,
               horizontalScrollRegions.isEmpty,
               beginsNewSequence {
                self.scrollOwner = nil
            } else {
                return scrollOwner
            }
        }
        let isInsideShelfSafetyRegion = horizontalScrollRegions.contains(where: {
            $0.contains(localLocation(of: event))
        })
        // A precise gesture that starts over the result rail belongs to that
        // rail for its full lifetime. This intentionally includes slightly
        // diagonal first deltas: otherwise the canvas can steal the gesture
        // before the user's horizontal intent becomes clear.
        let preciseShelfGesture = event.hasPreciseScrollingDeltas
            && isInsideShelfSafetyRegion
        let horizontalWheelGesture = isInsideShelfSafetyRegion
            && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        let owner: ScrollOwner = preciseShelfGesture || horizontalWheelGesture
            ? .horizontalShelf
            : .canvas
        scrollOwner = owner
        return owner
    }

    private func finishScrollSequenceIfNeeded(_ event: NSEvent) {
        let phaseEnded = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        let momentumEnded = event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled)
        if phaseEnded || momentumEnded
            || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
            scrollOwner = nil
        }
    }

    private var isPanInteractionActive: Bool {
        isSpacePanToolActive || isDraggingCanvas
    }

    private var panCursorIntent: CanvasPanCursorIntent {
        CanvasPanCursorIntent(
            isSpacePanToolActive: isSpacePanToolActive,
            isDraggingCanvas: isDraggingCanvas
        )
    }

    private func supportedKeyAction(for event: NSEvent) -> SupportedKeyAction? {
        let modifiers = event.modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift
        ])

        switch (event.keyCode, modifiers) {
        case (49, []):
            return .spacePan
        case (51, []), (117, []):
            return .deleteSelection
        case (0, [.command]):
            return .selectAll
        case (8, [.command]):
            return .copySelection
        case (9, [.command]):
            return .paste
        case (6, [.command]):
            return .undo
        case (6, [.command, .shift]):
            return .redo
        case (53, []):
            return .cancel
        default:
            return nil
        }
    }

    private func consumeKeyDown(_ event: NSEvent) -> NSEvent? {
        consumedKeyCodes.insert(event.keyCode)
        return nil
    }

    private func hasEnabledMenuKeyEquivalent(for event: NSEvent) -> Bool {
        guard let mainMenu = NSApp.mainMenu,
              let characters = event.charactersIgnoringModifiers?.lowercased(),
              !characters.isEmpty else { return false }
        let modifiers = event.modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift
        ])
        return menuItems(in: mainMenu).contains { item in
            item.isEnabled
                && item.keyEquivalent.lowercased() == characters
                && item.keyEquivalentModifierMask.intersection([
                    .command,
                    .control,
                    .option,
                    .shift
                ]) == modifiers
        }
    }

    private func menuItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in
            if let submenu = item.submenu {
                return [item] + menuItems(in: submenu)
            }
            return [item]
        }
    }

    private func isExplicitSwiftUIShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift
        ])
        guard modifiers == [.command, .shift] else { return false }
        // Toolbar shortcuts: new prompt, new generator, paste image.
        return [35, 5, 9].contains(event.keyCode)
    }

    private func shouldPreserveNativeNavigationKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.function) { return true }
        // Return, keypad Enter, Escape, Tab, arrows, Home, End, Page Up, Page Down.
        return [36, 76, 53, 48, 123, 124, 125, 126, 115, 119, 116, 121]
            .contains(event.keyCode)
    }

    private var keyboardRoutingContext: CanvasKeyboardRoutingContext {
        return CanvasKeyboardRoutingContext(
            isCanvasFirstResponder: monitoredWindow?.firstResponder === self
                && isCanvasCommandScopeActive,
            textResponderRole: activeTextResponderRole
        )
    }

    private var containsCurrentPointer: Bool {
        guard let monitoredWindow else { return false }
        let location = convert(monitoredWindow.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(location)
    }

    private func containsEventLocation(_ event: NSEvent) -> Bool {
        bounds.contains(localLocation(of: event))
    }

    private func localLocation(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func isTextInput(at windowLocation: CGPoint) -> Bool {
        guard let contentView = monitoredWindow?.contentView else { return false }
        let contentLocation = contentView.convert(windowLocation, from: nil)
        var candidate = contentView.hitTest(contentLocation)

        while let view = candidate {
            if let textView = view as? NSTextView,
               textView.isEditable || textView.isSelectable {
                return true
            }
            if let textField = view as? NSTextField,
               textField.isEditable || textField.isSelectable,
               textField.isEnabled {
                return true
            }
            candidate = view.superview
        }
        return false
    }

    private var activeTextResponderRole: CanvasTextResponderRole {
        guard let firstResponder = monitoredWindow?.firstResponder else { return .none }
        if let textView = firstResponder as? NSTextView {
            if textView.isEditable { return .editable }
            if textView.isSelectable { return .selectable }
            return .none
        }
        if let textField = firstResponder as? NSTextField {
            guard textField.isEnabled else { return .none }
            if textField.isEditable { return .editable }
            if textField.isSelectable { return .selectable }
        }
        return .none
    }

    private func isSelectableTextCommand(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift
        ])
        return (event.keyCode == 0 || event.keyCode == 8)
            && modifiers == [.command]
    }

    private func refreshCursor() {
        monitoredWindow?.invalidateCursorRects(for: self)
        guard containsCurrentPointer else { return }
        let pointer = monitoredWindow.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        if let cursor = pointer.flatMap(resolvedCursor(at:)) {
            cursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func resolvedCursor(at point: CGPoint) -> NSCursor? {
        if let panCursor = panCursorIntent.nsCursor { return panCursor }
        if let activeResizeEdge { return activeResizeEdge.nsCursor }
        return resizeCursorRegions.reversed().first { $0.rect.contains(point) }?.edge.nsCursor
    }

    private func resetPanInteraction(restoreArrowCursor: Bool) {
        isSpacePanToolActive = false
        isDraggingCanvas = false
        canvasDragButtonNumber = nil
        lastDragLocation = nil
        consumedKeyCodes.remove(49)
        reportPanInteractionIfNeeded()
        monitoredWindow?.invalidateCursorRects(for: self)
        if restoreArrowCursor, containsCurrentPointer {
            refreshCursor()
        }
    }

    private func handleMagnification(_ event: NSEvent) -> NSEvent? {
        let phase = event.phase

        if phase.contains(.began) {
            guard containsEventLocation(event), !isDraggingCanvas else { return event }
            beginMagnification(at: localLocation(of: event))
        } else if phase.isEmpty, !isMagnifyingCanvas {
            // Some synthetic devices omit gesture phases. Treat that event as
            // one complete incremental magnification without retaining state.
            guard containsEventLocation(event), !isDraggingCanvas else { return event }
            let anchor = localLocation(of: event)
            applyMagnification(event.magnification, around: anchor)
            return nil
        }

        guard isMagnifyingCanvas else { return event }

        if phase.contains(.cancelled) {
            resetMagnification()
            return nil
        }

        if let magnificationAnchor {
            applyMagnification(event.magnification, around: magnificationAnchor)
        }

        if phase.contains(.ended) {
            resetMagnification()
        }
        return nil
    }

    private func beginMagnification(at anchor: CGPoint) {
        guard !isMagnifyingCanvas else { return }
        isMagnifyingCanvas = true
        magnificationAnchor = anchor
        onCancelInteraction?()
        onZoomInteractionChanged?(true)
    }

    private func applyMagnification(_ magnification: CGFloat, around anchor: CGPoint) {
        guard magnification != 0 else { return }
        let factor = 1 + Double(magnification)
        guard factor.isFinite, factor > 0 else { return }
        onZoom?(factor, anchor)
    }

    private func resetMagnification() {
        guard isMagnifyingCanvas || magnificationAnchor != nil else { return }
        isMagnifyingCanvas = false
        magnificationAnchor = nil
        onZoomInteractionChanged?(false)
    }

    private func reportPanInteractionIfNeeded() {
        let currentState = isPanInteractionActive
        guard currentState != lastReportedPanInteractionState else { return }
        lastReportedPanInteractionState = currentState
        onPanInteractionChanged?(currentState)
    }

    @objc private func windowDidResignKey() {
        resetPanInteraction(restoreArrowCursor: false)
        resetMagnification()
    }
}

private enum SupportedKeyAction {
    case spacePan
    case deleteSelection
    case selectAll
    case copySelection
    case paste
    case undo
    case redo
    case cancel
}

private extension CanvasPanCursorIntent {
    var nsCursor: NSCursor? {
        switch self {
        case .systemDefault: nil
        case .openHand: .openHand
        case .closedHand: .closedHand
        }
    }
}

struct CanvasResizeCursorRegion: Equatable {
    let edge: CanvasNodeResizeEdge
    let rect: CGRect

    static func regions(
        in frame: CGRect,
        edgeThickness: CGFloat = 8,
        cornerSize: CGFloat = 16
    ) -> [Self] {
        guard frame.width > 0, frame.height > 0 else { return [] }
        let edge = min(edgeThickness, min(frame.width / 2, frame.height / 2))
        let corner = min(cornerSize, min(frame.width / 2, frame.height / 2))
        return [
            Self(edge: .top, rect: CGRect(x: frame.minX + corner, y: frame.minY, width: max(0, frame.width - 2 * corner), height: edge)),
            Self(edge: .right, rect: CGRect(x: frame.maxX - edge, y: frame.minY + corner, width: edge, height: max(0, frame.height - 2 * corner))),
            Self(edge: .bottom, rect: CGRect(x: frame.minX + corner, y: frame.maxY - edge, width: max(0, frame.width - 2 * corner), height: edge)),
            Self(edge: .left, rect: CGRect(x: frame.minX, y: frame.minY + corner, width: edge, height: max(0, frame.height - 2 * corner))),
            Self(edge: .topLeft, rect: CGRect(x: frame.minX, y: frame.minY, width: corner, height: corner)),
            Self(edge: .topRight, rect: CGRect(x: frame.maxX - corner, y: frame.minY, width: corner, height: corner)),
            Self(edge: .bottomLeft, rect: CGRect(x: frame.minX, y: frame.maxY - corner, width: corner, height: corner)),
            Self(edge: .bottomRight, rect: CGRect(x: frame.maxX - corner, y: frame.maxY - corner, width: corner, height: corner))
        ]
    }
}

private extension CanvasNodeResizeEdge {
    var nsCursor: NSCursor {
        let position: NSCursor.FrameResizePosition = switch self {
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        case .topLeft: .topLeft
        }
        return .frameResize(position: position, directions: .all)
    }
}
