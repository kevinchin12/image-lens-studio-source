/// Platform-neutral cursor intent for the temporary canvas pan tool.
public enum CanvasPanCursorIntent: Hashable, Sendable {
    case systemDefault
    case openHand
    case closedHand

    public init(isSpacePanToolActive: Bool, isDraggingCanvas: Bool) {
        if isDraggingCanvas {
            self = .closedHand
        } else if isSpacePanToolActive {
            self = .openHand
        } else {
            self = .systemDefault
        }
    }
}

/// Keyboard ownership for a canvas embedded beside editable UI.
///
/// Keyboard focus follows the responder chain, never pointer hover. Selectable
/// or editable text keeps every text command; otherwise only an explicitly
/// focused canvas owns its node commands. Sidebar and toolbar responders keep
/// their events in the native responder chain.
public struct CanvasKeyboardRoutingContext: Hashable, Sendable {
    public let isCanvasFirstResponder: Bool
    public let textResponderRole: CanvasTextResponderRole

    public init(
        isCanvasFirstResponder: Bool,
        textResponderRole: CanvasTextResponderRole
    ) {
        self.isCanvasFirstResponder = isCanvasFirstResponder
        self.textResponderRole = textResponderRole
    }

    public var canvasOwnsKeyboardInput: Bool {
        isCanvasFirstResponder && textResponderRole == .none
    }

    public var windowOwnsCanvasCommands: Bool {
        canvasOwnsKeyboardInput
    }
}

public enum CanvasTextResponderRole: Hashable, Sendable {
    case none
    case selectable
    case editable
}
