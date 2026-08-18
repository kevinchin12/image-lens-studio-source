import AppKit
import ImageLensCanvas
import ImageLensCore
import SwiftUI

struct CanvasSurfaceView: View {
    let session: WorkspaceSession
    @Binding var viewportSize: ViewSize
    let onImportMedia: () -> Void

    @State private var didInitializeUsableViewport = false
    @State private var connectionDraft: CanvasConnectionDraft?
    @State private var nodeDrag: CanvasNodeDragState?
    @State private var nodeResize: CanvasNodeResizeState?
    @State private var marquee: CanvasMarqueeState?
    @State private var isMarqueeCancelled = false
    @State private var isPanInteractionActive = false
    @State private var isZoomInteractionActive = false
    @State private var isImageDropTargeted = false
    @State private var promptTagDrag: CanvasPromptTagDragState?
    @State private var promptBundleDraft: CanvasPromptBundleDraft?
    @State private var referenceAssetDrag: CanvasReferenceAssetDraft?
    @State private var referenceDropTargets: [CanvasReferenceNodeDropTargetFrame] = []
    @State private var promptDropTargets: [CanvasPromptNodeDropTargetFrame] = []
    @State private var imagePromptSelections: [CanvasNodeID: Set<PromptModuleID>] = [:]
    @State private var activeImageChromeNodeID: CanvasNodeID?
    @State private var selectedConnectionID: CanvasConnectionSelectionID?
    @State private var horizontalScrollRegions: [CGRect] = []
    @State private var generatorOutputSelections: [GeneratorID: AssetID] = [:]

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = ViewSize(
                width: Double(proxy.size.width),
                height: Double(proxy.size.height)
            )
            let effectiveViewport = session.viewport

            canvasLayers(
                viewport: effectiveViewport,
                viewportSize: viewportSize
            )
            .coordinateSpace(name: CanvasCoordinateSpace.name)
            .contentShape(Rectangle())
            .dropDestination(for: URL.self) { urls, location in
                guard session.isReady,
                      !session.isImporting,
                      CanvasImageFileDrop.canAccept(urls) else { return false }
                Task {
                    _ = await session.importDroppedImages(
                        from: urls,
                        at: ViewPoint(x: Double(location.x), y: Double(location.y))
                    )
                }
                return true
            } isTargeted: { isTargeted in
                isImageDropTargeted = isTargeted
            }
            .contextMenu {
                canvasContextMenu(viewportSize: viewportSize)
            }
            .background(canvasInputBridge)
            .onAppear {
                self.viewportSize = viewportSize
                initializeViewportIfNeeded(viewportSize)
            }
            .onChange(of: proxy.size) { _, _ in
                self.viewportSize = viewportSize
                initializeViewportIfNeeded(viewportSize)
            }
            .onChange(of: promptTagDrag?.moduleID) { previous, current in
                handlePromptTagDragChange(previous: previous, current: current)
            }
            .onChange(of: promptBundleDraft?.sourceNodeID) { previous, current in
                handlePromptBundleDraftChange(previous: previous, current: current)
            }
            .onChange(of: connectionDraft?.moduleID) { previous, current in
                handleConnectionDraftChange(previous: previous, current: current)
            }
            .onPreferenceChange(CanvasReferenceNodeDropTargetPreferenceKey.self) { targets in
                referenceDropTargets = targets
            }
            .onPreferenceChange(CanvasPromptNodeDropTargetPreferenceKey.self) { targets in
                promptDropTargets = targets
            }
            .onPreferenceChange(CanvasHorizontalScrollRegionPreferenceKey.self) { regions in
                horizontalScrollRegions = regions
            }
            .onChange(of: session.selectedNodeIDs) { _, selectedNodeIDs in
                handleNodeSelectionChange(selectedNodeIDs)
            }
        }
        .background(.background)
        .clipped()
    }

    private func initializeViewportIfNeeded(_ size: ViewSize) {
        guard !didInitializeUsableViewport, size.width >= 400, size.height >= 300 else { return }
        session.resetViewport(viewportSize: size)
        didInitializeUsableViewport = true
    }

    private var selectedNodeCopyTitle: String {
        let count = session.selectedNodeIDs.count
        return count > 1 ? "复制 \(count) 个节点" : "复制节点"
    }

    private func canvasLayers(
        viewport: ViewportTransform,
        viewportSize: ViewSize
    ) -> some View {
        ZStack {
            CanvasGridView(viewport: viewport)

            CanvasMarqueeInteractionLayer(
                session: session,
                viewport: viewport,
                marquee: $marquee,
                isCancelled: $isMarqueeCancelled,
                isPanInteractionActive: $isPanInteractionActive,
                isZoomInteractionActive: isZoomInteractionActive,
                isPromptTagDragActive: connectionDraft != nil
                    || promptTagDrag != nil
                    || promptBundleDraft != nil
                    || referenceAssetDrag != nil,
                onClearTransientPromptSelections: {
                    imagePromptSelections.removeAll()
                },
                onClearConnectionSelection: {
                    selectedConnectionID = nil
                }
            )

            if !session.workspace.canvasNodes.isEmpty {
                CanvasConnectionsLayer(
                    session: session,
                    viewport: viewport,
                    connectionDraft: connectionDraft,
                    promptBundleDraft: promptBundleDraft,
                    referenceAssetDrag: referenceAssetDrag,
                    generatorOutputSelections: generatorOutputSelections,
                    nodeDrag: nodeDrag,
                    nodeResize: nodeResize,
                    selectedConnectionID: $selectedConnectionID,
                    isInteractionSuppressed: isPanInteractionActive
                        || isZoomInteractionActive
                        || referenceAssetDrag != nil,
                    onDisconnect: { connectionID in
                        disconnect(connectionID)
                    },
                    onDisconnectSourceModules: { groupID, moduleIDs in
                        guard !moduleIDs.isEmpty else { return }
                        selectedConnectionID = nil
                        Task {
                            await session.disconnectSourceModules(
                                moduleIDs,
                                from: groupID
                            )
                        }
                    }
                )
                CanvasNodesLayer(
                    session: session,
                    viewport: viewport,
                    viewportSize: viewportSize,
                    connectionDraft: $connectionDraft,
                    nodeDrag: $nodeDrag,
                    nodeResize: $nodeResize,
                    promptTagDrag: $promptTagDrag,
                    promptBundleDraft: $promptBundleDraft,
                    referenceAssetDrag: $referenceAssetDrag,
                    referenceDropTargets: referenceDropTargets,
                    promptDropTargets: promptDropTargets,
                    onReferenceDragEnded: { assetID, location in
                        finishReferenceAssetDrag(assetID: assetID, at: location)
                    },
                    imagePromptSelections: $imagePromptSelections,
                    activeImageChromeNodeID: $activeImageChromeNodeID,
                    generatorOutputSelections: $generatorOutputSelections,
                    isPanInteractionActive: isPanInteractionActive,
                    isZoomInteractionActive: isZoomInteractionActive
                )
            }

            CanvasSelectionBoundsLayer(
                session: session,
                viewport: viewport,
                nodeDrag: nodeDrag,
                nodeResize: nodeResize
            )

            if let marquee {
                CanvasMarqueeOverlay(marquee: marquee)
            }

            if let promptTagDrag {
                CanvasPromptTagDragOverlay(drag: promptTagDrag)
            }

            if let promptBundleDraft {
                CanvasPromptBundleDragOverlay(drag: promptBundleDraft)
            }

            if let referenceAssetDrag {
                CanvasReferenceAssetDragOverlay(drag: referenceAssetDrag)
            }

            if isImageDropTargeted {
                CanvasImageDropOverlay()
            }

            VStack {
                Spacer()
                CanvasControlsView(session: session, viewportSize: viewportSize)
                    .padding(.bottom, 16)
            }
        }
    }

    private var canvasInputBridge: some View {
        CanvasInputBridge(
            resizeCursorRegions: resizeCursorRegions,
            horizontalScrollRegions: horizontalScrollRegions,
            activeResizeEdge: nodeResize?.edge,
            onPan: { translation in
                session.panBy(
                    x: Double(translation.width),
                    y: Double(translation.height)
                )
            },
            onZoom: { factor, anchor in
                session.zoom(
                    by: factor,
                    around: ViewPoint(x: Double(anchor.x), y: Double(anchor.y))
                )
            },
            onDeleteSelection: {
                nodeResize = nil
                if let selectedConnectionID {
                    disconnect(selectedConnectionID)
                } else {
                    session.removeSelectedNodesFromCanvas()
                }
            },
            onSelectAll: {
                nodeResize = nil
                selectedConnectionID = nil
                session.selectAllCanvasNodes()
            },
            onCopySelection: {
                nodeResize = nil
                session.copySelectedCanvasNodes()
            },
            onPaste: {
                nodeResize = nil
                selectedConnectionID = nil
                Task {
                    await session.pasteCanvasContent(viewportSize: viewportSize)
                }
            },
            onUndo: {
                nodeResize = nil
                selectedConnectionID = nil
                session.undo()
            },
            onRedo: {
                nodeResize = nil
                selectedConnectionID = nil
                session.redo()
            },
            onCancelInteraction: {
                cancelMarqueeIfNeeded()
                connectionDraft = nil
                promptTagDrag = nil
                promptBundleDraft = nil
                referenceAssetDrag = nil
                imagePromptSelections.removeAll()
                nodeDrag = nil
                nodeResize = nil
                selectedConnectionID = nil
            },
            onPanInteractionChanged: { isActive in
                isPanInteractionActive = isActive
                if isActive {
                    cancelMarqueeIfNeeded()
                    nodeDrag = nil
                    promptTagDrag = nil
                    promptBundleDraft = nil
                    connectionDraft = nil
                    referenceAssetDrag = nil
                    nodeResize = nil
                }
            },
            onZoomInteractionChanged: { isActive in
                isZoomInteractionActive = isActive
                if isActive {
                    cancelMarqueeIfNeeded()
                    nodeDrag = nil
                    nodeResize = nil
                    promptTagDrag = nil
                    promptBundleDraft = nil
                    connectionDraft = nil
                }
            }
        )
    }

    private var resizeCursorRegions: [CanvasResizeCursorRegion] {
        let hiddenNodeIDs = session.collapsedGenerationGroupMemberNodeIDs
        return session.workspace.canvasNodes
            .sorted { $0.zIndex < $1.zIndex }
            .flatMap { node -> [CanvasResizeCursorRegion] in
                guard !hiddenNodeIDs.contains(node.id),
                      session.generationGroup(containing: node.id) == nil,
                      CanvasNodeRegistry.descriptor(
                        for: node,
                        in: session.workspace
                      ).supports(.resize) else { return [] }
                let frame = visibleResizeFrame(for: node)
                let viewRect = session.viewport.viewRect(for: frame)
                let rect = CGRect(
                    x: viewRect.origin.x,
                    y: viewRect.origin.y,
                    width: viewRect.size.width,
                    height: viewRect.size.height
                )
                var regions = CanvasResizeCursorRegion.regions(in: rect)
                guard node.kind == .module else { return regions }

                // The module output port owns the middle of the right edge.
                // Keep its connection affordance unambiguous while retaining
                // resize zones above and below it.
                regions.removeAll { $0.edge == .right }
                let edgeThickness: CGFloat = 8
                let cornerInset: CGFloat = 16
                let portHalfHeight = max(8, 18 * session.viewport.scale)
                let upperHeight = rect.midY - portHalfHeight - (rect.minY + cornerInset)
                if upperHeight > 0 {
                    regions.append(
                        CanvasResizeCursorRegion(
                            edge: .right,
                            rect: CGRect(
                                x: rect.maxX - edgeThickness,
                                y: rect.minY + cornerInset,
                                width: edgeThickness,
                                height: upperHeight
                            )
                        )
                    )
                }
                let lowerY = rect.midY + portHalfHeight
                let lowerHeight = rect.maxY - cornerInset - lowerY
                if lowerHeight > 0 {
                    regions.append(
                        CanvasResizeCursorRegion(
                            edge: .right,
                            rect: CGRect(
                                x: rect.maxX - edgeThickness,
                                y: lowerY,
                                width: edgeThickness,
                                height: lowerHeight
                            )
                        )
                    )
                }
                return regions
            }
    }

    private func visibleResizeFrame(for node: CanvasNode) -> WorldRect {
        let renderedFrame = nodeResize?.frame(for: node) ?? node.frame
        guard node.kind == .image,
              let assetID = node.imageAssetID,
              let asset = session.asset(for: assetID),
              !asset.isVideo else { return renderedFrame }
        return ImageNodeSurroundLayout(
            imageFrame: renderedFrame,
            contentAspectRatio: asset.contentAspectRatio,
            includesHeaderChrome: asset.supportsReversePrompt,
            includesAnalysisChrome: asset.supportsReversePrompt
        ).displayedImageFrame
    }

    @ViewBuilder
    private func canvasContextMenu(viewportSize: ViewSize) -> some View {
        Menu("添加", systemImage: "plus") {
            CanvasAddMenuContent(
                session: session,
                viewportSize: viewportSize,
                onImportMedia: onImportMedia
            )
        }
        Button("粘贴图片或视频", systemImage: "clipboard") {
            Task { await session.importClipboardMedia(viewportSize: viewportSize) }
        }
        Button("粘贴节点", systemImage: "doc.on.clipboard") {
            session.pasteCopiedCanvasNodes()
        }
        .disabled(!session.hasCurrentCanvasNodeClipboard)
        Divider()
        Button("全选画布节点", systemImage: "selection.pin.in.out") {
            session.selectAllCanvasNodes()
        }
        .disabled(session.workspace.canvasNodes.isEmpty)
        if !session.selectedNodeIDs.isEmpty {
            let removalPresentation = CanvasRemovalPresentation(session: session)
            Button(selectedNodeCopyTitle, systemImage: "doc.on.doc") {
                session.copySelectedCanvasNodes()
            }
            Button("取消选择", systemImage: "xmark.circle") {
                session.clearSelection()
            }
            Button(
                removalPresentation.title,
                systemImage: removalPresentation.systemImage,
                role: .destructive
            ) {
                session.removeSelectedNodesFromCanvas()
            }
            .help(removalPresentation.help)
        }
        Divider()
        Button("撤销", systemImage: "arrow.uturn.backward") {
            session.undo()
        }
        .disabled(session.undoDepth == 0)
        Button("重做", systemImage: "arrow.uturn.forward") {
            session.redo()
        }
        .disabled(session.redoDepth == 0)
        Divider()
        Button("重置画布视图", systemImage: "scope") {
            session.resetViewport(viewportSize: viewportSize)
        }
    }

    private func handlePromptTagDragChange(
        previous: PromptModuleID?,
        current: PromptModuleID?
    ) {
        guard previous == nil, current != nil else { return }
        cancelMarqueeIfNeeded()
        nodeDrag = nil
        nodeResize = nil
        connectionDraft = nil
        promptBundleDraft = nil
        selectedConnectionID = nil
    }

    private func handlePromptBundleDraftChange(
        previous: CanvasNodeID?,
        current: CanvasNodeID?
    ) {
        guard previous == nil, current != nil else { return }
        cancelMarqueeIfNeeded()
        nodeDrag = nil
        nodeResize = nil
        connectionDraft = nil
        promptTagDrag = nil
        selectedConnectionID = nil
    }

    private func handleConnectionDraftChange(
        previous: PromptModuleID?,
        current: PromptModuleID?
    ) {
        guard previous == nil, current != nil else { return }
        cancelMarqueeIfNeeded()
        nodeDrag = nil
        nodeResize = nil
        promptTagDrag = nil
        promptBundleDraft = nil
        referenceAssetDrag = nil
        selectedConnectionID = nil
    }

    private func handleNodeSelectionChange(_ selectedNodeIDs: Set<CanvasNodeID>) {
        if let nodeResize, !selectedNodeIDs.contains(nodeResize.nodeID) {
            self.nodeResize = nil
        }
        imagePromptSelections = imagePromptSelections.filter { nodeID, _ in
            selectedNodeIDs.contains(nodeID)
        }
        if let activeImageChromeNodeID,
           !selectedNodeIDs.contains(activeImageChromeNodeID) {
            self.activeImageChromeNodeID = nil
        }
        guard !selectedNodeIDs.isEmpty else { return }
        selectedConnectionID = nil
    }

    private func cancelMarqueeIfNeeded() {
        guard let marquee else { return }
        session.setSelection(
            marquee.baseline.nodeIDs,
            preferredPrimary: marquee.baseline.primaryNodeID
        )
        isMarqueeCancelled = true
        self.marquee = nil
    }

    private func disconnect(_ connectionID: CanvasConnectionSelectionID) {
        selectedConnectionID = nil
        switch connectionID {
        case .recipeBinding(_, let recipeID, let bindingID):
            Task {
                await session.disconnect(
                    graphEdgeID: .recipeBinding(
                        recipeID: recipeID,
                        bindingID: bindingID
                    )
                )
            }
        case .sourceModuleGroup(let groupID):
            let moduleIDs = SourceModuleConnectionProjection(workspace: session.workspace)
                .groups
                .first(where: { $0.id == groupID })?
                .moduleIDs ?? []
            guard !moduleIDs.isEmpty else { return }
            Task {
                await session.disconnectSourceModules(
                    moduleIDs,
                    from: groupID
                )
            }
        case .assetReference(let generatorID, let assetID):
            Task {
                await session.unbindReferenceAsset(assetID, from: generatorID)
            }
        }
    }

    private func finishReferenceAssetDrag(
        assetID: AssetID,
        at location: CGPoint
    ) {
        let draft = referenceAssetDrag
        let target = referenceDropTargets
            .last(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(location) })?
            .target
        let mediaKind = draft?.mediaKind ?? .unknown
        referenceAssetDrag = nil
        guard let target else {
            session.statusMessage = "请拖到图片生成或视频生成节点"
            return
        }
        guard target.generatorID != draft?.sourceGeneratorID else {
            session.statusMessage = "生成结果不能作为同一节点自己的参考"
            return
        }
        guard target.accepts(mediaKind) else {
            session.statusMessage = mediaKind == .video
                ? "当前参考槽不支持视频素材"
                : "当前参考槽不支持这项素材"
            return
        }
        Task {
            await session.assignReferenceAsset(
                assetID,
                to: target.generatorID,
                sourceCanvasNodeID: draft?.sourceNodeID
            )
        }
    }
}

private enum CanvasCoordinateSpace {
    static let name = "ImageLensCanvasCoordinateSpace"
}

private struct CanvasImageDropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            Color.accentColor.opacity(0.75),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                        )
                }
                .padding(12)

            Label("松开以导入图片或视频", systemImage: "rectangle.stack.badge.plus")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CanvasConnectionDraft {
    let moduleID: PromptModuleID
    let start: CGPoint
    let current: CGPoint
}

private struct CanvasPromptTagDragState {
    let sourceNodeID: CanvasNodeID
    let moduleID: PromptModuleID
    let category: PromptModuleCategory
    let start: CGPoint
    let current: CGPoint
}

private struct CanvasPromptBundleDraft {
    let sourceNodeID: CanvasNodeID
    let sourceAssetID: AssetID
    let moduleIDs: [PromptModuleID]
    let start: CGPoint
    let current: CGPoint
}

private struct CanvasReferenceAssetDraft {
    let sourceNodeID: CanvasNodeID
    let sourceAssetID: AssetID
    let sourceGeneratorID: GeneratorID?
    let mediaKind: AssetMediaKind
    let start: CGPoint
    let current: CGPoint
}

private struct CanvasPromptTagDragOverlay: View {
    let drag: CanvasPromptTagDragState

    var body: some View {
        Label(drag.category.displayName, systemImage: "text.badge.plus")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.accentColor.opacity(0.55), lineWidth: 1) }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            .position(drag.current)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CanvasPromptBundleDragOverlay: View {
    let drag: CanvasPromptBundleDraft

    var body: some View {
        Label("\(drag.moduleIDs.count) 项提示词", systemImage: "text.quote")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.indigo)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.indigo.opacity(0.55), lineWidth: 1) }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            .position(drag.current)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CanvasReferenceAssetDragOverlay: View {
    let drag: CanvasReferenceAssetDraft

    var body: some View {
        Canvas { context, _ in
            let delta = max(56, abs(drag.current.x - drag.start.x) * 0.42)
            var path = Path()
            path.move(to: drag.start)
            path.addCurve(
                to: drag.current,
                control1: CGPoint(x: drag.start.x + delta, y: drag.start.y),
                control2: CGPoint(x: drag.current.x - delta, y: drag.current.y)
            )
            context.stroke(
                path,
                with: .color(Color.accentColor),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CanvasMarqueeState {
    let start: CGPoint
    var current: CGPoint
    let baseline: CanvasNodeSelection
    let mutation: CanvasSelectionMutation

    var viewRect: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}

private struct CanvasNodeDragState {
    let anchorNodeID: CanvasNodeID
    let nodeIDs: Set<CanvasNodeID>
    let viewTranslation: CGSize
    let generationGroupID: CanvasGenerationGroupID?
    let extractingFromGenerationGroupID: CanvasGenerationGroupID?

    init(
        anchorNodeID: CanvasNodeID,
        nodeIDs: Set<CanvasNodeID>,
        viewTranslation: CGSize,
        generationGroupID: CanvasGenerationGroupID? = nil,
        extractingFromGenerationGroupID: CanvasGenerationGroupID? = nil
    ) {
        self.anchorNodeID = anchorNodeID
        self.nodeIDs = nodeIDs
        self.viewTranslation = viewTranslation
        self.generationGroupID = generationGroupID
        self.extractingFromGenerationGroupID = extractingFromGenerationGroupID
    }

    func offset(for candidateID: CanvasNodeID) -> CGSize {
        nodeIDs.contains(candidateID) ? viewTranslation : .zero
    }

    func frame(for node: CanvasNode, viewportScale: Double) -> WorldRect {
        guard nodeIDs.contains(node.id), viewportScale > 0 else { return node.frame }
        return WorldRect(
            origin: WorldPoint(
                x: node.frame.origin.x + Double(viewTranslation.width) / viewportScale,
                y: node.frame.origin.y + Double(viewTranslation.height) / viewportScale
            ),
            size: node.frame.size
        )
    }

    func frame(
        forGenerationGroup groupID: CanvasGenerationGroupID,
        frame: WorldRect,
        viewportScale: Double
    ) -> WorldRect {
        guard generationGroupID == groupID, viewportScale > 0 else { return frame }
        return WorldRect(
            origin: WorldPoint(
                x: frame.origin.x + Double(viewTranslation.width) / viewportScale,
                y: frame.origin.y + Double(viewTranslation.height) / viewportScale
            ),
            size: frame.size
        )
    }
}

private struct CanvasNodeResizeState {
    let nodeID: CanvasNodeID
    let originalFrame: WorldRect
    let initialFrame: WorldRect
    let candidateFrame: WorldRect
    let edge: CanvasNodeResizeEdge

    func frame(for node: CanvasNode) -> WorldRect {
        node.id == nodeID ? candidateFrame : node.frame
    }
}

private struct CanvasMarqueeInteractionLayer: View {
    let session: WorkspaceSession
    let viewport: ViewportTransform
    @Binding var marquee: CanvasMarqueeState?
    @Binding var isCancelled: Bool
    @Binding var isPanInteractionActive: Bool
    let isZoomInteractionActive: Bool
    let isPromptTagDragActive: Bool
    let onClearTransientPromptSelections: () -> Void
    let onClearConnectionSelection: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isPanInteractionActive,
                      !isZoomInteractionActive,
                      !isPromptTagDragActive,
                      !NSEvent.modifierFlags.contains(.shift) else { return }
                session.clearSelection()
                onClearTransientPromptSelections()
                onClearConnectionSelection()
            }
            .gesture(
                DragGesture(
                    minimumDistance: 3,
                    coordinateSpace: .named(CanvasCoordinateSpace.name)
                )
                .onChanged { value in
                    guard !isCancelled,
                          !isPanInteractionActive,
                          !isZoomInteractionActive,
                          !isPromptTagDragActive else { return }
                    if marquee == nil {
                        onClearTransientPromptSelections()
                        onClearConnectionSelection()
                    }
                    var next = marquee ?? CanvasMarqueeState(
                        start: value.startLocation,
                        current: value.location,
                        baseline: CanvasNodeSelection(
                            nodeIDs: session.selectedNodeIDs,
                            primaryNodeID: session.selectedNodeID
                        ),
                        mutation: NSEvent.modifierFlags.contains(.shift) ? .add : .replace
                    )
                    next.current = value.location

                    let worldRect = viewport.worldRect(
                        for: ViewRect(
                            x: Double(next.viewRect.minX),
                            y: Double(next.viewRect.minY),
                            width: Double(next.viewRect.width),
                            height: Double(next.viewRect.height)
                        )
                    )
                    let hiddenNodeIDs = session.collapsedGenerationGroupMemberNodeIDs
                    var placements = session.workspace.canvasNodes
                        .filter { !hiddenNodeIDs.contains($0.id) }
                        .map(CanvasNodePlacement.init(node:))
                    placements.append(contentsOf: session.workspace.generationGroups.compactMap { group in
                        guard group.isCollapsed,
                              let representativeID = group.memberNodeIDs.first else { return nil }
                        return CanvasNodePlacement(
                            id: representativeID.rawValue,
                            frame: session.generationGroupLayout(for: group).bounds,
                            zIndex: Int.max - 1
                        )
                    })
                    let selection = next.baseline.applyingMarquee(
                        to: placements,
                        in: worldRect,
                        mutation: next.mutation
                    )
                    marquee = next
                    session.setSelection(
                        session.expandingCollapsedGenerationGroupSelection(selection.nodeIDs),
                        preferredPrimary: selection.primaryNodeID
                    )
                }
                .onEnded { _ in
                    guard !isPromptTagDragActive else { return }
                    marquee = nil
                    isCancelled = false
                }
            )
            .accessibilityLabel("画布空白区域")
            .accessibilityHint("拖动以框选节点")
    }
}

private struct CanvasMarqueeOverlay: View {
    let marquee: CanvasMarqueeState

    var body: some View {
        let rect = marquee.viewRect
        Rectangle()
            .fill(Color.accentColor.opacity(0.08))
            .overlay {
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.85), lineWidth: 1)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CanvasSelectionBoundsLayer: View {
    let session: WorkspaceSession
    let viewport: ViewportTransform
    let nodeDrag: CanvasNodeDragState?
    let nodeResize: CanvasNodeResizeState?

    var body: some View {
        if let rect = selectionViewRect {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                )
                .frame(width: rect.width + 14, height: rect.height + 14)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var selectionViewRect: CGRect? {
        guard session.selectedNodeIDs.count > 1 else { return nil }
        let collapsedMemberIDs = session.collapsedGenerationGroupMemberNodeIDs
        var frames = session.workspace.canvasNodes.compactMap { node -> WorldRect? in
            guard session.selectedNodeIDs.contains(node.id) else { return nil }
            guard !collapsedMemberIDs.contains(node.id) else { return nil }
            let resizedFrame = nodeResize?.frame(for: node) ?? node.frame
            var resizedNode = node
            resizedNode.frame = resizedFrame
            return nodeDrag?.frame(for: resizedNode, viewportScale: viewport.scale) ?? resizedFrame
        }
        frames.append(contentsOf: session.workspace.generationGroups.compactMap { group in
            guard group.isCollapsed,
                  !session.selectedNodeIDs.isDisjoint(with: group.memberNodeIDs) else { return nil }
            let frame = session.generationGroupLayout(for: group).bounds
            return nodeDrag?.frame(
                forGenerationGroup: group.id,
                frame: frame,
                viewportScale: viewport.scale
            ) ?? frame
        })
        guard let first = frames.first else { return nil }
        let worldBounds = frames.dropFirst().reduce(first) { bounds, frame in
            WorldRect(
                x: min(bounds.minX, frame.minX),
                y: min(bounds.minY, frame.minY),
                width: max(bounds.maxX, frame.maxX) - min(bounds.minX, frame.minX),
                height: max(bounds.maxY, frame.maxY) - min(bounds.minY, frame.minY)
            )
        }
        let rect = viewport.viewRect(for: worldBounds)
        return CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}

private struct CanvasGenerationGroupsLayer: View {
    let session: WorkspaceSession
    let viewport: ViewportTransform
    @Binding var nodeDrag: CanvasNodeDragState?
    let isDragSuppressed: Bool

    var body: some View {
        ForEach(session.workspace.generationGroups) { group in
            let layout = session.generationGroupLayout(for: group)
            let rect = viewport.viewRect(for: layout.bounds)
            CanvasGenerationGroupView(
                session: session,
                group: group,
                layout: layout,
                scale: viewport.scale,
                nodeDrag: $nodeDrag,
                isDragSuppressed: isDragSuppressed
            )
            .frame(
                width: CGFloat(rect.size.width),
                height: CGFloat(rect.size.height)
            )
            .position(
                x: CGFloat(rect.origin.x + rect.size.width / 2),
                y: CGFloat(rect.origin.y + rect.size.height / 2)
            )
            .offset(
                nodeDrag?.generationGroupID == group.id
                    ? nodeDrag?.viewTranslation ?? .zero
                    : .zero
            )
        }
    }
}

private struct CanvasGenerationGroupView: View {
    let session: WorkspaceSession
    let group: CanvasGenerationGroup
    let layout: GenerationGroupLayout
    let scale: Double
    @Binding var nodeDrag: CanvasNodeDragState?
    let isDragSuppressed: Bool
    @State private var isRenaming = false
    @State private var nameDraft = ""
    @FocusState private var isNameFieldFocused: Bool

    private var isSelected: Bool {
        !session.selectedNodeIDs.isDisjoint(with: group.memberNodeIDs)
    }

    private var title: String {
        let name = WorkspaceDisplayNamePolicy.normalized(group.name ?? "")
        return name.isEmpty ? "生成结果" : name
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                .fill(
                    group.isCollapsed
                        ? Color(nsColor: .controlBackgroundColor).opacity(0.96)
                        : Color.accentColor.opacity(0.035)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.22),
                            style: StrokeStyle(
                                lineWidth: (isSelected ? 2 : 1) * scale,
                                dash: group.isCollapsed ? [] : [7 * scale, 6 * scale]
                            )
                        )
                }

            HStack(spacing: 8 * scale) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(Color.accentColor)
                if isRenaming {
                    TextField("生成结果组名称", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .focused($isNameFieldFocused)
                        .frame(
                            minWidth: 90 * scale,
                            maxWidth: 220 * scale
                        )
                        .onSubmit(commitRename)
                        .onExitCommand(perform: cancelRename)
                } else {
                    Text(title)
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .lineLimit(1)
                        .onTapGesture(count: 2, perform: beginRename)
                        .help("双击重命名")
                }
                Text("\(group.memberNodeIDs.count) 张")
                    .font(.system(size: 11 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4 * scale)
                Button {
                    session.toggleGenerationGroup(group.id)
                } label: {
                    Image(systemName: group.isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10 * scale, weight: .bold))
                        .frame(width: 24 * scale, height: 24 * scale)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help(group.isCollapsed ? "展开生成结果" : "折叠生成结果")
            }
            .padding(.horizontal, 2 * scale)
            .frame(
                width: layout.headerFrame.width * scale,
                height: layout.headerFrame.height * scale
            )
            .offset(
                x: (layout.headerFrame.minX - layout.bounds.minX) * scale,
                y: (layout.headerFrame.minY - layout.bounds.minY) * scale
            )

            if group.isCollapsed {
                Text("生成内容已收起，点击展开查看")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
                    .offset(x: 26 * scale, y: 64 * scale)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
        .onTapGesture {
            session.selectGenerationGroup(group.id)
        }
        .gesture(
            DragGesture(
                minimumDistance: 3,
                coordinateSpace: .named(CanvasCoordinateSpace.name)
            )
            .onChanged { value in
                guard !isRenaming,
                      !isDragSuppressed,
                      let anchorNodeID = group.memberNodeIDs.first else { return }
                if nodeDrag?.generationGroupID != group.id {
                    session.selectGenerationGroup(group.id)
                }
                nodeDrag = CanvasNodeDragState(
                    anchorNodeID: anchorNodeID,
                    nodeIDs: Set(group.memberNodeIDs),
                    viewTranslation: value.translation,
                    generationGroupID: group.id
                )
            }
            .onEnded { value in
                guard !isRenaming, !isDragSuppressed else {
                    nodeDrag = nil
                    return
                }
                let translation = nodeDrag?.generationGroupID == group.id
                    ? nodeDrag?.viewTranslation ?? value.translation
                    : value.translation
                nodeDrag = nil
                guard scale > 0 else { return }
                session.moveGenerationGroup(
                    id: group.id,
                    byWorldTranslation: WorldSize(
                        width: Double(translation.width) / scale,
                        height: Double(translation.height) / scale
                    )
                )
            }
        )
        .contextMenu {
            Button("重命名…", systemImage: "pencil") {
                beginRename()
            }
            Button(
                group.isCollapsed ? "展开结果组" : "折叠结果组",
                systemImage: group.isCollapsed ? "chevron.down" : "chevron.up"
            ) {
                session.toggleGenerationGroup(group.id)
            }
            Button("从画布移除结果组", systemImage: "rectangle.badge.minus", role: .destructive) {
                session.removeGenerationGroupFromCanvas(group.id)
            }
        }
        .onChange(of: isRenaming) { _, renaming in
            if renaming { isNameFieldFocused = true }
        }
        .onChange(of: isNameFieldFocused) { wasFocused, isFocused in
            if wasFocused, !isFocused, isRenaming {
                commitRename()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title)，\(group.memberNodeIDs.count) 张生成图片")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func beginRename() {
        nameDraft = title
        isRenaming = true
    }

    private func commitRename() {
        let name = WorkspaceDisplayNamePolicy.normalized(nameDraft)
        guard !name.isEmpty else {
            cancelRename()
            return
        }
        isRenaming = false
        isNameFieldFocused = false
        session.renameGenerationGroup(id: group.id, to: name)
    }

    private func cancelRename() {
        nameDraft = title
        isRenaming = false
        isNameFieldFocused = false
    }
}

private struct CanvasNodesLayer: View {
    let session: WorkspaceSession
    let viewport: ViewportTransform
    let viewportSize: ViewSize
    @Binding var connectionDraft: CanvasConnectionDraft?
    @Binding var nodeDrag: CanvasNodeDragState?
    @Binding var nodeResize: CanvasNodeResizeState?
    @Binding var promptTagDrag: CanvasPromptTagDragState?
    @Binding var promptBundleDraft: CanvasPromptBundleDraft?
    @Binding var referenceAssetDrag: CanvasReferenceAssetDraft?
    let referenceDropTargets: [CanvasReferenceNodeDropTargetFrame]
    let promptDropTargets: [CanvasPromptNodeDropTargetFrame]
    let onReferenceDragEnded: (AssetID, CGPoint) -> Void
    @Binding var imagePromptSelections: [CanvasNodeID: Set<PromptModuleID>]
    @Binding var activeImageChromeNodeID: CanvasNodeID?
    @Binding var generatorOutputSelections: [GeneratorID: AssetID]
    let isPanInteractionActive: Bool
    let isZoomInteractionActive: Bool

    var body: some View {
        let hiddenNodeIDs = session.collapsedGenerationGroupMemberNodeIDs
        let renderableNodes = session.workspace.canvasNodes.filter { !hiddenNodeIDs.contains($0.id) }
        let placements = renderableNodes.map(cullingPlacement(for:))
        let visibleIDs: Set<UUID> = {
            var ids = Set(
                CanvasCulling.visiblePlacements(
                    from: placements,
                    transform: viewport,
                    viewportSize: viewportSize,
                    overscanInViewPoints: 80
                ).map(\.id)
            )
            // A transient drag can move well beyond the persisted frame used
            // by the spatial index. Keep every dragged node alive until
            // mouse-up so culling cannot cancel the gesture at a viewport edge.
            if let nodeDrag {
                ids.formUnion(nodeDrag.nodeIDs.map(\.rawValue))
            }
            if let nodeResize {
                ids.insert(nodeResize.nodeID.rawValue)
            }
            return ids
        }()

        ForEach(
            renderableNodes
                .filter { visibleIDs.contains($0.id.rawValue) }
                .sorted { $0.zIndex < $1.zIndex }
        ) { node in
            let renderedNode = nodeWithResizePreview(node)
            let rect = viewport.viewRect(for: renderedNode.frame)
            switch node.kind {
            case .image:
                if let assetID = node.imageAssetID,
                   let asset = session.asset(for: assetID) {
                let showsStructuredPromptChrome = !asset.isVideo
                    && session.latestAnalysisSnapshot(for: asset.id) != nil
                    && !session.analysisModules(for: asset.id).isEmpty
                    && !session.isAnalyzing(asset.id)
                    && asset.state != .failed
                let shellRect = viewport.viewRect(
                    for: asset.isVideo
                        ? VideoCanvasChrome.shellFrame(
                            around: renderedNode.frame,
                            showsControls: (
                                session.selectedNodeID == node.id
                                    || session.activeVideoNodeID == node.id
                            ) && viewport.scale >= 0.5
                        )
                        : ImageCanvasChrome.shellFrame(
                            around: renderedNode.frame,
                            includesHeaderChrome: asset.supportsReversePrompt,
                            includesAnalysisChrome: asset.supportsReversePrompt,
                            includesStructuredPromptChrome: showsStructuredPromptChrome
                        )
                )
                let visibleImageFrame = ImageNodeSurroundLayout(
                    imageFrame: renderedNode.frame,
                    contentAspectRatio: asset.isVideo ? nil : asset.contentAspectRatio,
                    includesHeaderChrome: asset.supportsReversePrompt,
                    includesAnalysisChrome: asset.supportsReversePrompt,
                    includesStructuredPromptChrome: showsStructuredPromptChrome
                ).displayedImageFrame
                let visibleImageRect = viewport.viewRect(for: visibleImageFrame)
                Group {
                    if asset.isVideo {
                        VideoCanvasNodeView(
                            session: session,
                            node: renderedNode,
                            asset: asset,
                            scale: viewport.scale,
                            viewport: viewport,
                            activeDrag: $nodeDrag,
                            showsReferenceDragHandle: asset.supportsMediaReference,
                            isNodeDragSuppressed: nodeResize != nil
                                || isPanInteractionActive
                                || isZoomInteractionActive
                                || referenceAssetDrag != nil,
                            onReferenceDragChanged: { start, current in
                                nodeDrag = nil
                                nodeResize = nil
                                connectionDraft = nil
                                promptTagDrag = nil
                                promptBundleDraft = nil
                                referenceAssetDrag = CanvasReferenceAssetDraft(
                                    sourceNodeID: node.id,
                                    sourceAssetID: asset.id,
                                    sourceGeneratorID: GeneratorReferenceConnectionPolicy.sourceGeneratorID(
                                        for: asset,
                                        generations: session.workspace.generations
                                    ),
                                    mediaKind: asset.mediaKind,
                                    start: start,
                                    current: current
                                )
                            },
                            onReferenceDragEnded: { location in
                                guard referenceAssetDrag?.sourceNodeID == node.id else {
                                    referenceAssetDrag = nil
                                    return
                                }
                                onReferenceDragEnded(asset.id, location)
                            }
                        )
                    } else {
                        ImageCanvasNodeView(
                            session: session,
                            node: renderedNode,
                            asset: asset,
                            scale: viewport.scale,
                            viewport: viewport,
                            activeDrag: $nodeDrag,
                            selectedPromptModuleIDs: [],
                            showsReferenceDragHandle: asset.supportsMediaReference,
                            isNodeDragSuppressed: promptTagDrag != nil
                                || promptBundleDraft != nil
                                || referenceAssetDrag != nil
                                || nodeResize != nil
                                || isPanInteractionActive
                                || isZoomInteractionActive,
                            onChromeActivityChanged: { isActive in
                                if isActive {
                                    activeImageChromeNodeID = node.id
                                } else if activeImageChromeNodeID == node.id,
                                          promptTagDrag?.sourceNodeID != node.id {
                                    activeImageChromeNodeID = nil
                                }
                            },
                            onPromptTagDragChanged: { module, category, start, current in
                                activeImageChromeNodeID = node.id
                                imagePromptSelections[node.id] = nil
                                promptTagDrag = CanvasPromptTagDragState(
                                    sourceNodeID: node.id,
                                    moduleID: module.id,
                                    category: category,
                                    start: start,
                                    current: current
                                )
                            },
                            onPromptTagDragEnded: { module, _, location in
                                guard !isPanInteractionActive,
                                      !isZoomInteractionActive,
                                      promptTagDrag?.sourceNodeID == node.id,
                                      promptTagDrag?.moduleID == module.id else {
                                    promptTagDrag = nil
                                    return
                                }
                                finishPromptConnection(
                                    moduleID: module.id,
                                    at: location
                                )
                                promptTagDrag = nil
                            },
                            onPromptSelectionToggle: { _ in },
                            onReferenceDragChanged: { start, current in
                                nodeDrag = nil
                                nodeResize = nil
                                connectionDraft = nil
                                promptTagDrag = nil
                                promptBundleDraft = nil
                                imagePromptSelections[node.id] = nil
                                activeImageChromeNodeID = node.id
                                referenceAssetDrag = CanvasReferenceAssetDraft(
                                    sourceNodeID: node.id,
                                    sourceAssetID: asset.id,
                                    sourceGeneratorID: GeneratorReferenceConnectionPolicy.sourceGeneratorID(
                                        for: asset,
                                        generations: session.workspace.generations
                                    ),
                                    mediaKind: asset.mediaKind,
                                    start: start,
                                    current: current
                                )
                            },
                            onReferenceDragEnded: { location in
                                guard referenceAssetDrag?.sourceNodeID == node.id else {
                                    referenceAssetDrag = nil
                                    return
                                }
                                onReferenceDragEnded(asset.id, location)
                            },
                            onPromptBundleDragChanged: { moduleIDs, start, current in
                                activeImageChromeNodeID = node.id
                                promptBundleDraft = CanvasPromptBundleDraft(
                                    sourceNodeID: node.id,
                                    sourceAssetID: asset.id,
                                    moduleIDs: moduleIDs,
                                    start: start,
                                    current: current
                                )
                            },
                            onPromptBundleDragEnded: { moduleIDs, location in
                                finishPromptBundleConnection(
                                    moduleIDs: moduleIDs,
                                    sourceNodeID: node.id,
                                    sourceAssetID: asset.id,
                                    at: location
                                )
                                promptBundleDraft = nil
                            }
                        )
                    }
                }
                .frame(
                    width: CGFloat(shellRect.size.width),
                    height: CGFloat(shellRect.size.height)
                )
                .overlay(alignment: .topLeading) {
                    if canResize(node) {
                        nodeResizeRegions(for: node)
                            .frame(
                                width: CGFloat(visibleImageRect.size.width),
                                height: CGFloat(visibleImageRect.size.height)
                            )
                            .position(
                                x: CGFloat(
                                    visibleImageRect.origin.x
                                        + visibleImageRect.size.width / 2
                                        - shellRect.origin.x
                                ),
                                y: CGFloat(
                                    visibleImageRect.origin.y
                                        + visibleImageRect.size.height / 2
                                        - shellRect.origin.y
                                )
                            )
                    }
                }
                .position(
                    x: CGFloat(shellRect.origin.x + shellRect.size.width / 2),
                    y: CGFloat(shellRect.origin.y + shellRect.size.height / 2)
                )
                .zIndex(
                    activeImageChromeNodeID == node.id || session.isNodeSelected(node.id)
                        ? 100_000 + Double(node.zIndex)
                        : Double(node.zIndex)
                )
                }
            case .module:
                if let moduleID = node.promptModuleID,
                   let module = session.promptModule(for: moduleID) {
                    let handleCenterOffset = PromptModuleNodeChrome.connectionHandleCenterOffset
                        * viewport.scale
                    let rightGutter = PromptModuleNodeChrome.rightGutter * viewport.scale

                    ZStack(alignment: .topLeading) {
                        PromptModuleCanvasNodeView(
                            session: session,
                            node: renderedNode,
                            module: module,
                            scale: viewport.scale
                        )
                        .frame(
                            width: CGFloat(rect.size.width),
                            height: CGFloat(rect.size.height)
                        )
                        .position(
                            x: CGFloat(rect.size.width / 2),
                            y: CGFloat(rect.size.height / 2)
                        )

                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: CGFloat(rect.size.width),
                                height: 30 * viewport.scale
                            )
                            .position(
                                x: CGFloat(rect.size.width / 2),
                                y: 15 * viewport.scale
                            )
                            .modifier(
                                CanvasNodeDragModifier(
                                    session: session,
                                    node: node,
                                    viewport: viewport,
                                    activeDrag: $nodeDrag,
                                    isDragSuppressed: connectionDraft != nil
                                        || promptTagDrag != nil
                                        || promptBundleDraft != nil
                                        || nodeResize != nil
                                        || isPanInteractionActive
                                        || isZoomInteractionActive,
                                    appliesOffset: false
                                )
                            )
                            .onTapGesture {
                                session.select(
                                    node.id,
                                    extending: NSEvent.modifierFlags.contains(.shift)
                                )
                            }

                        PromptConnectionHandle(
                            scale: viewport.scale,
                            isConnecting: connectionDraft?.moduleID == module.id,
                            onChanged: { start, current in
                                nodeDrag = nil
                                nodeResize = nil
                                promptTagDrag = nil
                                promptBundleDraft = nil
                                referenceAssetDrag = nil
                                connectionDraft = CanvasConnectionDraft(
                                    moduleID: module.id,
                                    start: start,
                                    current: current
                                )
                            },
                            onEnded: { location in
                                guard connectionDraft?.moduleID == module.id else {
                                    connectionDraft = nil
                                    return
                                }
                                finishMaterializedPromptConnection(
                                    moduleID: module.id,
                                    at: location
                                )
                                connectionDraft = nil
                            }
                        )
                        .position(
                            x: CGFloat(rect.size.width + handleCenterOffset),
                            y: CGFloat(rect.size.height / 2)
                        )
                        .zIndex(2)
                    }
                    .frame(
                        width: CGFloat(rect.size.width + rightGutter),
                        height: CGFloat(rect.size.height)
                    )
                    .position(
                        x: CGFloat(rect.origin.x + (rect.size.width + rightGutter) / 2),
                        y: CGFloat(rect.origin.y + rect.size.height / 2)
                    )
                    .offset(nodeDrag?.offset(for: node.id) ?? .zero)
                    .zIndex(Double(node.zIndex))
                }
            case .text:
                if let textBlockID = node.textBlockID,
                   let textBlock = session.textBlock(for: textBlockID) {
                    TextBlockCanvasNodeView(
                        session: session,
                        node: renderedNode,
                        textBlock: textBlock,
                        scale: viewport.scale
                    )
                    .frame(
                        width: CGFloat(rect.size.width),
                        height: CGFloat(rect.size.height)
                    )
                    .overlay {
                        if canResize(node) { nodeResizeRegions(for: node) }
                    }
                    .position(
                        x: CGFloat(rect.origin.x + rect.size.width / 2),
                        y: CGFloat(rect.origin.y + rect.size.height / 2)
                    )
                    .modifier(
                        CanvasNodeDragModifier(
                            session: session,
                            node: node,
                            viewport: viewport,
                            activeDrag: $nodeDrag,
                            isDragSuppressed: nodeResize != nil
                                || isPanInteractionActive
                                || isZoomInteractionActive
                        )
                    )
                    .zIndex(Double(node.zIndex))
                }
            case .generation:
                if let generatorID = node.generatorID,
                   let generator = session.generator(for: generatorID) {
                    let outputBatches = session.generationOutputBatches(for: generatorID)
                    let batchCount = outputBatches.count
                    let showsOutputShelf = batchCount > 0 && session.isNodeSelected(node.id)
                    let outputAssets = outputBatches.flatMap(\.assets)
                    let selectedOutputAsset = generatorOutputSelections[generatorID]
                        .flatMap { selectedID in
                            outputAssets.first(where: { $0.id == selectedID })
                        }
                        ?? outputBatches.last?.assets.first
                    let shellFrame = GeneratorNodeLayoutPolicy.shellFrame(
                        around: renderedNode.frame,
                        outputBatchCount: showsOutputShelf ? batchCount : 0
                    )
                    let shellRect = viewport.viewRect(for: shellFrame)
                    let shelfHeight = max(0, shellRect.size.height - rect.size.height)
                    let outputRailRect = GeneratorNodeLayoutPolicy.outputRailFrame(
                        around: renderedNode.frame,
                        outputBatchCount: showsOutputShelf ? batchCount : 0
                    ).map(viewport.viewRect(for:))

                    ZStack(alignment: .topLeading) {
                        if let outputRailRect {
                            GeneratorOutputRailView(
                                session: session,
                                nodeID: node.id,
                                generatorID: generatorID,
                                mediaKind: generator.mediaKind,
                                scale: viewport.scale,
                                coordinateSpaceName: CanvasCoordinateSpace.name,
                                selectedOutputAssetID: $generatorOutputSelections[generatorID]
                            )
                            .frame(
                                width: CGFloat(outputRailRect.size.width),
                                height: CGFloat(outputRailRect.size.height)
                            )
                            .position(
                                x: CGFloat(outputRailRect.origin.x - shellRect.origin.x
                                    + outputRailRect.size.width / 2),
                                y: CGFloat(outputRailRect.origin.y - shellRect.origin.y
                                    + outputRailRect.size.height / 2)
                            )
                            .zIndex(3)
                        }

                        GeneratorCanvasNodeView(
                            session: session,
                            node: renderedNode,
                            generator: generator,
                            scale: viewport.scale,
                            isResizePreview: nodeResize?.nodeID == node.id,
                            coordinateSpaceName: CanvasCoordinateSpace.name,
                            isReferenceDropTargeted: targetedReferenceTarget(for: generator.id) != nil,
                            targetedReferenceIsCompatible: targetedReferenceTarget(for: generator.id)?.accepts(
                                referenceAssetDrag?.mediaKind ?? .unknown
                            ) ?? false,
                            isPromptDropTargeted: targetedPromptTarget(for: generator.id) != nil,
                            selectedOutputAssetID: $generatorOutputSelections[generatorID]
                        )
                        .frame(
                            width: CGFloat(rect.size.width),
                            height: CGFloat(rect.size.height)
                        )
                        .position(
                            x: CGFloat(rect.size.width / 2),
                            y: CGFloat(shelfHeight + rect.size.height / 2)
                        )
                        .modifier(
                            CanvasNodeDragModifier(
                                session: session,
                                node: node,
                                viewport: viewport,
                                activeDrag: $nodeDrag,
                                isDragSuppressed: connectionDraft != nil
                                    || promptTagDrag != nil
                                    || promptBundleDraft != nil
                                    || referenceAssetDrag != nil
                                    || nodeResize != nil
                                    || isPanInteractionActive
                                    || isZoomInteractionActive,
                                appliesOffset: false
                            )
                        )
                        .zIndex(1)

                        if let selectedOutputAsset,
                           session.isNodeSelected(node.id)
                            || referenceAssetDrag?.sourceNodeID == node.id {
                            let handleCenter = GeneratorNodeLayoutPolicy.outputReferenceHandleCenter(
                                in: renderedNode.frame,
                                contentAspectRatio: selectedOutputAsset.contentAspectRatio
                            )
                            let handleCenterInView = viewport.viewPoint(for: handleCenter)
                            let localHandleCenter = CGPoint(
                                x: handleCenterInView.x - shellRect.origin.x,
                                y: handleCenterInView.y - shellRect.origin.y
                            )

                            MediaReferenceDragHandle(
                                mediaKind: selectedOutputAsset.mediaKind,
                                scale: viewport.scale,
                                coordinateSpaceName: CanvasCoordinateSpace.name,
                                onDragActivityChanged: { _ in },
                                onDragChanged: { _, current in
                                    nodeDrag = nil
                                    nodeResize = nil
                                    connectionDraft = nil
                                    promptTagDrag = nil
                                    promptBundleDraft = nil
                                    referenceAssetDrag = CanvasReferenceAssetDraft(
                                        sourceNodeID: node.id,
                                        sourceAssetID: selectedOutputAsset.id,
                                        sourceGeneratorID: generatorID,
                                        mediaKind: selectedOutputAsset.mediaKind,
                                        start: CGPoint(
                                            x: handleCenterInView.x,
                                            y: handleCenterInView.y
                                        ),
                                        current: current
                                    )
                                },
                                onDragEnded: { location in
                                    guard referenceAssetDrag?.sourceNodeID == node.id,
                                          referenceAssetDrag?.sourceAssetID
                                            == selectedOutputAsset.id else {
                                        referenceAssetDrag = nil
                                        return
                                    }
                                    onReferenceDragEnded(selectedOutputAsset.id, location)
                                },
                                hoverDiameter: GeneratorNodeLayoutPolicy.outputReferenceHandleHitDiameter,
                                minimumHoverDiameter: 0
                            )
                            .position(
                                x: localHandleCenter.x,
                                y: localHandleCenter.y
                            )
                            .zIndex(4)
                        }
                    }
                    .frame(
                        width: CGFloat(shellRect.size.width),
                        height: CGFloat(shellRect.size.height)
                    )
                    .position(
                        x: CGFloat(shellRect.origin.x + shellRect.size.width / 2),
                        y: CGFloat(shellRect.origin.y + shellRect.size.height / 2)
                    )
                    .offset(nodeDrag?.offset(for: node.id) ?? .zero)
                    .zIndex(
                        session.isNodeSelected(node.id)
                            || referenceAssetDrag?.sourceNodeID == node.id
                            ? 100_000 + Double(node.zIndex)
                            : Double(node.zIndex)
                    )
                }
            case .recipe:
                EmptyView()
            }
        }
    }

    private func nodeWithResizePreview(_ node: CanvasNode) -> CanvasNode {
        var result = node
        result.frame = nodeResize?.frame(for: node) ?? node.frame
        return result
    }

    private func cullingPlacement(for node: CanvasNode) -> CanvasNodePlacement {
        guard node.kind == .generation,
              let generatorID = node.generatorID else {
            return CanvasNodePlacement(node: node)
        }
        let batchCount = session.generationOutputBatches(for: generatorID).count
        let visibleBatchCount = session.isNodeSelected(node.id) ? batchCount : 0
        return CanvasNodePlacement(
            id: node.id.rawValue,
            frame: GeneratorNodeLayoutPolicy.shellFrame(
                around: node.frame,
                outputBatchCount: visibleBatchCount
            ),
            zIndex: node.zIndex
        )
    }

    private func canResize(_ node: CanvasNode) -> Bool {
        CanvasNodeRegistry.descriptor(for: node, in: session.workspace).supports(.resize)
            && session.generationGroup(containing: node.id) == nil
            && !isPanInteractionActive
            && !isZoomInteractionActive
            && referenceAssetDrag == nil
            && (nodeResize == nil || nodeResize?.nodeID == node.id)
    }

    private func targetedReferenceTarget(
        for generatorID: GeneratorID
    ) -> CanvasReferenceNodeDropTarget? {
        guard let location = referenceAssetDrag?.current else { return nil }
        return referenceDropTargets
            .last {
                $0.target.generatorID == generatorID
                    && $0.target.generatorID != referenceAssetDrag?.sourceGeneratorID
                    && $0.frame.insetBy(dx: -4, dy: -4).contains(location)
            }?
            .target
    }

    private func nodeResizeRegions(for node: CanvasNode) -> some View {
        CanvasNodeResizeRegions(
            onChanged: { edge, translation in
                updateResizePreview(for: node, edge: edge, translation: translation)
            },
            onEnded: { edge, translation in
                finishResize(for: node, edge: edge, translation: translation)
            }
        )
    }

    private func updateResizePreview(
        for node: CanvasNode,
        edge: CanvasNodeResizeEdge,
        translation: CGSize
    ) {
        guard !isPanInteractionActive, !isZoomInteractionActive else { return }
        if !session.isNodeSelected(node.id) {
            session.setSelection([node.id], preferredPrimary: node.id)
        }
        let originalFrame = nodeResize?.nodeID == node.id
            ? nodeResize?.originalFrame ?? node.frame
            : node.frame
        let initialFrame = nodeResize?.nodeID == node.id
            ? nodeResize?.initialFrame ?? resizeInitialFrame(for: node)
            : resizeInitialFrame(for: node)
        let candidate = resizeFrame(
            for: node,
            initialFrame: initialFrame,
            edge: edge,
            translation: translation
        )
        nodeDrag = nil
        connectionDraft = nil
        promptTagDrag = nil
        promptBundleDraft = nil
        nodeResize = CanvasNodeResizeState(
            nodeID: node.id,
            originalFrame: originalFrame,
            initialFrame: initialFrame,
            candidateFrame: candidate,
            edge: edge
        )
    }

    private func finishResize(
        for node: CanvasNode,
        edge: CanvasNodeResizeEdge,
        translation: CGSize
    ) {
        let originalFrame = nodeResize?.nodeID == node.id
            ? nodeResize?.originalFrame ?? node.frame
            : node.frame
        let initialFrame = nodeResize?.nodeID == node.id
            ? nodeResize?.initialFrame ?? resizeInitialFrame(for: node)
            : resizeInitialFrame(for: node)
        let candidate = resizeFrame(
            for: node,
            initialFrame: initialFrame,
            edge: edge,
            translation: translation
        )
        let command = CanvasNodeResizeCommand(
            nodeID: node.id,
            fromFrame: originalFrame,
            toFrame: candidate
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            nodeResize = nil
            session.applyCanvasNodeResize(command)
        }
    }

    private func resizeInitialFrame(for node: CanvasNode) -> WorldRect {
        guard node.kind == .image,
              let assetID = node.imageAssetID,
              let asset = session.asset(for: assetID),
              !asset.isVideo else { return node.frame }
        return ImageNodeSurroundLayout(
            imageFrame: node.frame,
            contentAspectRatio: asset.contentAspectRatio,
            includesHeaderChrome: asset.supportsReversePrompt,
            includesAnalysisChrome: asset.supportsReversePrompt
        ).displayedImageFrame
    }

    private func resizeFrame(
        for node: CanvasNode,
        initialFrame: WorldRect,
        edge: CanvasNodeResizeEdge,
        translation: CGSize
    ) -> WorldRect {
        var policy = CanvasNodeResizePolicy.standard(for: node.kind)
        let viewTranslation = ViewDragTranslation(
            x: Double(translation.width),
            y: Double(translation.height)
        )
        if node.kind == .generation, let generatorID = node.generatorID,
           let generator = session.generator(for: generatorID) {
            let preliminary = policy.frame(
                from: initialFrame,
                viewTranslation: viewTranslation,
                viewportScale: viewport.scale,
                edge: edge
            )
            let compiledPreview = session.compiledPreview(for: generator)
            let structuredInputs = compiledPreview?.moduleInputs.filter {
                $0.role.visualCategory != nil
            } ?? []
            let subjectLines = structuredInputs
                .filter { $0.role == .visual(.subject) }
                .map(structuredPromptDisplayText)
            let trailingLines = structuredInputs
                .filter { $0.role != .visual(.subject) }
                .map(structuredPromptDisplayText)
            let promptLayout = GeneratorPromptLayout(
                prompt: generator.promptText,
                leadingReadOnlyLines: subjectLines,
                trailingReadOnlyLines: trailingLines,
                nodeWidth: preliminary.width,
                baseNodeHeight: session.collapsedGeneratorNodeHeight
                    + (generator.imageEdit == nil
                        ? 0
                        : GeneratorNodeLayoutPolicy.imageEditSupplementaryHeight)
            )
            policy.minimumSize.height = promptLayout.requiredNodeHeight
        }
        return policy.frame(
            from: initialFrame,
            viewTranslation: viewTranslation,
            viewportScale: viewport.scale,
            edge: edge
        )
    }

    private func structuredPromptDisplayText(_ input: ModuleInputSnapshot) -> String {
        let title = input.role.visualCategory?.displayName ?? "提示"
        return "\(title)  \(input.resolvedContent)"
    }

    private func finishPromptConnection(moduleID: PromptModuleID, at location: CGPoint) {
        if let target = promptDropTarget(at: location) {
            Task { await session.connect(moduleID: moduleID, to: target.generatorID) }
        } else {
            session.materializePromptModule(
                id: moduleID,
                at: ViewPoint(x: Double(location.x), y: Double(location.y))
            )
        }
    }

    private func finishMaterializedPromptConnection(
        moduleID: PromptModuleID,
        at location: CGPoint
    ) {
        guard let target = promptDropTarget(at: location) else {
            session.statusMessage = "请把连线拖到图片或视频生成节点"
            return
        }
        Task { await session.connect(moduleID: moduleID, to: target.generatorID) }
    }

    private func togglePromptSelection(
        _ moduleID: PromptModuleID,
        for sourceNodeID: CanvasNodeID
    ) {
        var selection = imagePromptSelections[sourceNodeID] ?? []
        if selection.remove(moduleID) == nil {
            selection.insert(moduleID)
        }
        imagePromptSelections = selection.isEmpty ? [:] : [sourceNodeID: selection]
    }

    private func finishPromptBundleConnection(
        moduleIDs: [PromptModuleID],
        sourceNodeID: CanvasNodeID,
        sourceAssetID: AssetID,
        at location: CGPoint
    ) {
        imagePromptSelections[sourceNodeID] = nil
        guard let target = promptDropTarget(at: location) else {
            session.statusMessage = "请把已选结构化提示词拖到图片或视频生成节点"
            return
        }
        Task {
            _ = await session.connectAnalysisModules(
                moduleIDs: moduleIDs,
                sourceAssetID: sourceAssetID,
                to: target.generatorID
            )
        }
    }

    private func promptDropTarget(at location: CGPoint) -> CanvasPromptNodeDropTarget? {
        promptDropTargets
            .last { $0.frame.insetBy(dx: -4, dy: -4).contains(location) }?
            .target
    }

    private func targetedPromptTarget(
        for generatorID: GeneratorID
    ) -> CanvasPromptNodeDropTarget? {
        let location = connectionDraft?.current
            ?? promptTagDrag?.current
            ?? promptBundleDraft?.current
        guard let location else { return nil }
        return promptDropTargets
            .last {
                $0.target.generatorID == generatorID
                    && $0.frame.insetBy(dx: -4, dy: -4).contains(location)
            }?
            .target
    }

    private func contains(_ point: CGPoint, in rect: ViewRect) -> Bool {
        let minX = rect.origin.x
        let minY = rect.origin.y
        return Double(point.x) >= minX
            && Double(point.x) <= minX + rect.size.width
            && Double(point.y) >= minY
            && Double(point.y) <= minY + rect.size.height
    }
}

private struct CanvasNodeDragModifier: ViewModifier {
    let session: WorkspaceSession
    let node: CanvasNode
    let viewport: ViewportTransform
    @Binding var activeDrag: CanvasNodeDragState?
    let isDragSuppressed: Bool
    var appliesOffset = true

    @GestureState private var isGestureActive = false

    func body(content: Content) -> some View {
        content
            .offset(appliesOffset ? (activeDrag?.offset(for: node.id) ?? .zero) : .zero)
            .gesture(
                DragGesture(
                    minimumDistance: 3,
                    coordinateSpace: .named(CanvasCoordinateSpace.name)
                )
                    .updating($isGestureActive) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        guard !isDragSuppressed else { return }
                        if let activeDrag, activeDrag.anchorNodeID == node.id {
                            self.activeDrag = CanvasNodeDragState(
                                anchorNodeID: activeDrag.anchorNodeID,
                                nodeIDs: activeDrag.nodeIDs,
                                viewTranslation: value.translation,
                                generationGroupID: activeDrag.generationGroupID,
                                extractingFromGenerationGroupID:
                                    activeDrag.extractingFromGenerationGroupID
                            )
                        } else {
                            if let generationGroup = session.generationGroup(containing: node.id) {
                                if let assetID = node.imageAssetID,
                                   session.asset(for: assetID)?.kind == .generated {
                                    session.setSelection([node.id], preferredPrimary: node.id)
                                    activeDrag = CanvasNodeDragState(
                                        anchorNodeID: node.id,
                                        nodeIDs: [node.id],
                                        viewTranslation: value.translation,
                                        extractingFromGenerationGroupID: generationGroup.id
                                    )
                                } else {
                                    session.selectGenerationGroup(generationGroup.id)
                                    activeDrag = CanvasNodeDragState(
                                        anchorNodeID: node.id,
                                        nodeIDs: Set(generationGroup.memberNodeIDs),
                                        viewTranslation: value.translation,
                                        generationGroupID: generationGroup.id
                                    )
                                }
                            } else {
                                if !session.isNodeSelected(node.id) {
                                // Selecting because a drag began must not open
                                // the inspector and resize the canvas mid-gesture.
                                    session.setSelection([node.id], preferredPrimary: node.id)
                                }
                                activeDrag = CanvasNodeDragState(
                                    anchorNodeID: node.id,
                                    nodeIDs: session.selectedNodeIDs.isEmpty
                                        ? [node.id]
                                        : session.selectedNodeIDs,
                                    viewTranslation: value.translation
                                )
                            }
                        }
                    }
                    .onEnded { value in
                        guard !isDragSuppressed else {
                            activeDrag = nil
                            return
                        }
                        let finalTranslation = activeDrag?.anchorNodeID == node.id
                            ? activeDrag?.viewTranslation ?? value.translation
                            : value.translation
                        if let sourceGroupID = activeDrag?.extractingFromGenerationGroupID {
                            guard viewport.scale > 0,
                                  let sourceGroup = session.generationGroup(id: sourceGroupID) else {
                                activeDrag = nil
                                return
                            }
                            let worldTranslation = WorldSize(
                                width: Double(finalTranslation.width) / viewport.scale,
                                height: Double(finalTranslation.height) / viewport.scale
                            )
                            let candidateCenter = WorldPoint(
                                x: node.frame.minX + worldTranslation.width + node.frame.width / 2,
                                y: node.frame.minY + worldTranslation.height + node.frame.height / 2
                            )
                            guard !session.generationGroupLayout(for: sourceGroup)
                                .bounds.contains(candidateCenter) else {
                                activeDrag = nil
                                return
                            }
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                activeDrag = nil
                                session.extractGeneratedResultAsSource(
                                    nodeID: node.id,
                                    from: sourceGroupID,
                                    byWorldTranslation: worldTranslation
                                )
                            }
                            return
                        }
                        if let generationGroupID = activeDrag?.generationGroupID {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                activeDrag = nil
                                guard viewport.scale > 0 else { return }
                                session.moveGenerationGroup(
                                    id: generationGroupID,
                                    byWorldTranslation: WorldSize(
                                        width: Double(finalTranslation.width) / viewport.scale,
                                        height: Double(finalTranslation.height) / viewport.scale
                                    )
                                )
                            }
                            return
                        }
                        let command = CanvasNodeGroupMoveCommand(
                            nodes: session.workspace.canvasNodes,
                            selectedNodeIDs: activeDrag?.nodeIDs ?? [node.id],
                            viewTranslation: ViewDragTranslation(
                                x: Double(finalTranslation.width),
                                y: Double(finalTranslation.height)
                            ),
                            viewport: viewport
                        )
                        guard !command.isNoOp else {
                            activeDrag = nil
                            return
                        }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            // Commit the persisted frame and clear the visual
                            // offset in one render transaction, avoiding a frame
                            // where both translations are applied.
                            activeDrag = nil
                            session.applyCanvasNodeGroupMove(command)
                        }
                    }
            )
            .onChange(of: isGestureActive) { wasActive, isActive in
                guard wasActive, !isActive, activeDrag?.anchorNodeID == node.id else { return }
                activeDrag = nil
            }
            .onChange(of: isDragSuppressed) { _, isSuppressed in
                guard isSuppressed, activeDrag?.anchorNodeID == node.id else { return }
                activeDrag = nil
            }
            .onDisappear {
                guard activeDrag?.anchorNodeID == node.id else { return }
                activeDrag = nil
            }
    }
}

private struct CanvasNodeResizeRegions: View {
    let onChanged: (CanvasNodeResizeEdge, CGSize) -> Void
    let onEnded: (CanvasNodeResizeEdge, CGSize) -> Void

    private let edgeThickness: CGFloat = 8
    private let cornerSize: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                resizeRegion(
                    .top,
                    frame: CGRect(
                        x: cornerSize,
                        y: 0,
                        width: max(0, proxy.size.width - 2 * cornerSize),
                        height: edgeThickness
                    )
                )
                resizeRegion(
                    .right,
                    frame: CGRect(
                        x: max(0, proxy.size.width - edgeThickness),
                        y: cornerSize,
                        width: edgeThickness,
                        height: max(0, proxy.size.height - 2 * cornerSize)
                    )
                )
                resizeRegion(
                    .bottom,
                    frame: CGRect(
                        x: cornerSize,
                        y: max(0, proxy.size.height - edgeThickness),
                        width: max(0, proxy.size.width - 2 * cornerSize),
                        height: edgeThickness
                    )
                )
                resizeRegion(
                    .left,
                    frame: CGRect(
                        x: 0,
                        y: cornerSize,
                        width: edgeThickness,
                        height: max(0, proxy.size.height - 2 * cornerSize)
                    )
                )
                resizeRegion(.topLeft, frame: CGRect(x: 0, y: 0, width: cornerSize, height: cornerSize))
                resizeRegion(
                    .topRight,
                    frame: CGRect(
                        x: max(0, proxy.size.width - cornerSize),
                        y: 0,
                        width: cornerSize,
                        height: cornerSize
                    )
                )
                resizeRegion(
                    .bottomLeft,
                    frame: CGRect(
                        x: 0,
                        y: max(0, proxy.size.height - cornerSize),
                        width: cornerSize,
                        height: cornerSize
                    )
                )
                resizeRegion(
                    .bottomRight,
                    frame: CGRect(
                        x: max(0, proxy.size.width - cornerSize),
                        y: max(0, proxy.size.height - cornerSize),
                        width: cornerSize,
                        height: cornerSize
                    )
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func resizeRegion(
        _ edge: CanvasNodeResizeEdge,
        frame: CGRect
    ) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .highPriorityGesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named(CanvasCoordinateSpace.name)
                )
                .onChanged { value in onChanged(edge, value.translation) }
                .onEnded { value in onEnded(edge, value.translation) }
            )
    }
}

private enum PromptModuleNodeChrome {
    static let connectionHandleCenterOffset = 0.0
    static let rightGutter = 15.0
}

private struct PromptConnectionHandle: View {
    let scale: Double
    let isConnecting: Bool
    let onChanged: (CGPoint, CGPoint) -> Void
    let onEnded: (CGPoint) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 18 * scale, height: 18 * scale)
                Image(systemName: "plus")
                    .font(.system(size: 8 * scale, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 18 * scale, height: 18 * scale)
            }
            .highPriorityGesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named(CanvasCoordinateSpace.name)
                )
                .onChanged { value in
                    let frame = proxy.frame(in: .named(CanvasCoordinateSpace.name))
                    onChanged(
                        CGPoint(x: frame.midX, y: frame.midY),
                        value.location
                    )
                }
                .onEnded { value in
                    onEnded(value.location)
                }
            )
        }
        .frame(width: 30 * scale, height: 36 * scale)
        .scaleEffect(isConnecting ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: isConnecting)
        .help("拖到图片或视频生成节点以连接")
        .accessibilityLabel("连接端口")
        .accessibilityHint("拖到图片或视频生成节点以补充提示词")
    }
}

private struct GeneratorConnectionTarget: View {
    let scale: Double
    let isActive: Bool
    let isTargeted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isTargeted ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            Circle()
                .stroke(
                    isActive ? Color.accentColor : Color.secondary.opacity(0.42),
                    lineWidth: (isTargeted ? 3 : 2) * scale
                )
            Image(systemName: isTargeted ? "checkmark" : "plus")
                .font(.system(size: 8 * scale, weight: .bold))
                .foregroundStyle(isTargeted ? Color.white : Color.secondary)
        }
        .frame(
            width: (isTargeted ? 22 : 18) * scale,
            height: (isTargeted ? 22 : 18) * scale
        )
        .frame(width: 30 * scale, height: 36 * scale)
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CanvasConnectionsLayer: View {
    let session: WorkspaceSession
    let viewport: ViewportTransform
    let connectionDraft: CanvasConnectionDraft?
    let promptBundleDraft: CanvasPromptBundleDraft?
    let referenceAssetDrag: CanvasReferenceAssetDraft?
    let generatorOutputSelections: [GeneratorID: AssetID]
    let nodeDrag: CanvasNodeDragState?
    let nodeResize: CanvasNodeResizeState?
    @Binding var selectedConnectionID: CanvasConnectionSelectionID?
    let isInteractionSuppressed: Bool
    let onDisconnect: (CanvasConnectionSelectionID) -> Void
    let onDisconnectSourceModules: (
        SourceModuleConnectionGroupID,
        [PromptModuleID]
    ) -> Void

    @State private var hoveredConnectionID: CanvasConnectionSelectionID?

    var body: some View {
        let renderedSegments = segments
        let validSelectionIDs = Set(renderedSegments.compactMap(\.selectionID))
        let interactionIsSuppressed = isInteractionSuppressed
            || connectionDraft != nil
            || promptBundleDraft != nil
            || nodeDrag != nil
            || nodeResize != nil

        ZStack {
            Canvas { context, _ in
                for segment in renderedSegments {
                    let geometry = CanvasConnectionViewGeometry(
                        segment: segment,
                        viewport: viewport
                    )
                    // Read-only lineage has no selection ID. Unwrap before
                    // comparing so nil == nil never looks selected or hovered.
                    let isSelected: Bool
                    let isHovered: Bool
                    if let selectionID = segment.selectionID {
                        isSelected = selectionID == selectedConnectionID
                        isHovered = selectionID == hoveredConnectionID
                    } else {
                        isSelected = false
                        isHovered = false
                    }
                    let color = segmentColor(
                        for: segment.style,
                        emphasized: isSelected || isHovered
                    )

                    if isSelected {
                        context.stroke(
                            geometry.path,
                            with: .color(color.opacity(0.16)),
                            style: StrokeStyle(
                                lineWidth: 9,
                                lineCap: .round
                            )
                        )
                    }
                    context.stroke(
                        geometry.path,
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: isSelected
                                ? 3.6
                                : segment.style.lineWidth,
                            lineCap: .round
                        )
                    )

                    if isSelected {
                        for point in [geometry.start, geometry.end] {
                            let marker = Path(
                                ellipseIn: CGRect(
                                    x: point.x - 4,
                                    y: point.y - 4,
                                    width: 8,
                                    height: 8
                                )
                            )
                            context.fill(marker, with: .color(color))
                        }
                    }
                }

                if let connectionDraft {
                    let horizontalDistance = max(
                        48,
                        abs(connectionDraft.current.x - connectionDraft.start.x) * 0.45
                    )
                    var path = Path()
                    path.move(to: connectionDraft.start)
                    path.addCurve(
                        to: connectionDraft.current,
                        control1: CGPoint(
                            x: connectionDraft.start.x + horizontalDistance,
                            y: connectionDraft.start.y
                        ),
                        control2: CGPoint(
                            x: connectionDraft.current.x - horizontalDistance,
                            y: connectionDraft.current.y
                        )
                    )
                    context.stroke(
                        path,
                        with: .color(.accentColor.opacity(0.9)),
                        style: StrokeStyle(
                            lineWidth: 2.5,
                            lineCap: .round,
                            dash: [7, 5]
                        )
                    )
                }

                if let promptBundleDraft {
                    let horizontalDistance = max(
                        48,
                        abs(promptBundleDraft.current.x - promptBundleDraft.start.x) * 0.45
                    )
                    var path = Path()
                    path.move(to: promptBundleDraft.start)
                    path.addCurve(
                        to: promptBundleDraft.current,
                        control1: CGPoint(
                            x: promptBundleDraft.start.x + horizontalDistance,
                            y: promptBundleDraft.start.y
                        ),
                        control2: CGPoint(
                            x: promptBundleDraft.current.x - horizontalDistance,
                            y: promptBundleDraft.current.y
                        )
                    )
                    context.stroke(
                        path,
                        with: .color(.indigo.opacity(0.95)),
                        style: StrokeStyle(
                            lineWidth: 2.5,
                            lineCap: .round,
                            dash: [7, 5]
                        )
                    )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            ForEach(renderedSegments.filter(\.isEditable)) { segment in
                CanvasConnectionInteractionView(
                    session: session,
                    segment: segment,
                    viewport: viewport,
                    selectedConnectionID: $selectedConnectionID,
                    hoveredConnectionID: $hoveredConnectionID,
                    isInteractionSuppressed: interactionIsSuppressed,
                    onDisconnect: onDisconnect,
                    onDisconnectSourceModules: onDisconnectSourceModules
                )
            }
        }
        .onChange(of: validSelectionIDs) { _, validIDs in
            guard let selectedConnectionID,
                  !validIDs.contains(selectedConnectionID) else { return }
            self.selectedConnectionID = nil
        }
        .onChange(of: interactionIsSuppressed) { _, isSuppressed in
            guard isSuppressed else { return }
            hoveredConnectionID = nil
        }
        .onChange(of: validSelectionIDs) { _, validIDs in
            guard let hoveredConnectionID,
                  !validIDs.contains(hoveredConnectionID) else { return }
            self.hoveredConnectionID = nil
        }
    }

    private var segments: [ConnectionSegment] {
        var result: [ConnectionSegment] = []
        var nodesByEntityID: [UUID: [CanvasNode]] = [:]
        for persistedNode in session.workspace.canvasNodes {
            var renderedNode = persistedNode
            renderedNode.frame = nodeResize?.frame(for: persistedNode) ?? persistedNode.frame
            renderedNode.frame = nodeDrag?.frame(
                for: renderedNode,
                viewportScale: viewport.scale
            ) ?? renderedNode.frame
            nodesByEntityID[renderedNode.entityID, default: []].append(renderedNode)
        }

        for generator in session.canvasGenerators {
            guard let generatorNode = nodesByEntityID[generator.id.rawValue]?.first,
                  let recipe = session.recipe(for: generator.recipeID) else { continue }

            for binding in recipe.bindings where binding.isEnabled {
                guard let moduleNode = closestNode(
                    to: generatorNode,
                    among: nodesByEntityID[binding.moduleID.rawValue] ?? []
                ) else { continue }
                result.append(
                    ConnectionSegment(
                        id: .recipeBinding(
                            generatorID: generator.id,
                            recipeID: recipe.id,
                            bindingID: binding.id
                        ),
                        selectionID: .recipeBinding(
                            generatorID: generator.id,
                            recipeID: recipe.id,
                            bindingID: binding.id
                        ),
                        style: .prompt,
                        start: WorldPoint(
                            x: moduleNode.frame.maxX
                                + PromptModuleNodeChrome.connectionHandleCenterOffset,
                            y: moduleNode.frame.minY + moduleNode.frame.height / 2
                        ),
                        end: WorldPoint(
                            x: generatorNode.frame.minX,
                            y: generatorNode.frame.minY + GeneratorNodeLayoutPolicy.inputAnchorY
                        ),
                        sourceTitle: promptModuleTitle(binding.moduleID),
                        targetTitle: generator.mediaKind == .video ? "视频生成" : "图片生成"
                    )
                )
            }

            let referenceBindingsByAsset = Dictionary(
                grouping: generator.assetBindings.filter(\.isEnabled),
                by: \.assetID
            )
            for (assetID, bindings) in referenceBindingsByAsset {
                guard let asset = session.asset(for: assetID) else { continue }
                let sourceAnchor: WorldPoint
                let preferredSourceNodeID = bindings.compactMap(\.sourceCanvasNodeID).first
                if let assetNode = CanvasReferenceSourceNodeResolver.resolve(
                    assetID: assetID,
                    preferredNodeID: preferredSourceNodeID,
                    among: nodesByEntityID[assetID.rawValue] ?? []
                ) {
                    sourceAnchor = imageLayout(
                        for: assetNode,
                        asset: asset
                    ).trailingImageConnectionAnchor
                } else if let sourceGeneratorNode = embeddedOutputGeneratorNode(
                    for: asset,
                    nodesByEntityID: nodesByEntityID
                ) {
                    let displayedAspectRatio = displayedOutputAsset(
                        for: sourceGeneratorNode
                    )?.contentAspectRatio ?? asset.contentAspectRatio
                    let showsReferenceHandle = session.isNodeSelected(sourceGeneratorNode.id)
                        || referenceAssetDrag?.sourceNodeID == sourceGeneratorNode.id
                    sourceAnchor = showsReferenceHandle
                        ? GeneratorNodeLayoutPolicy.outputReferenceHandleCenter(
                            in: sourceGeneratorNode.frame,
                            contentAspectRatio: displayedAspectRatio
                        )
                        : GeneratorNodeLayoutPolicy.outputReferenceNodeEdgeAnchor(
                            in: sourceGeneratorNode.frame,
                            contentAspectRatio: displayedAspectRatio
                        )
                } else {
                    continue
                }
                result.append(
                    ConnectionSegment(
                        id: .assetReference(generatorID: generator.id, assetID: assetID),
                        selectionID: .assetReference(generatorID: generator.id, assetID: assetID),
                        style: .reference,
                        start: sourceAnchor,
                        end: WorldPoint(
                            x: generatorNode.frame.minX,
                            y: generatorNode.frame.minY
                                + GeneratorNodeLayoutPolicy.referenceAnchorY
                        ),
                        sourceTitle: asset.displayName,
                        targetTitle: "\(generator.name) · \(bindings.count) 项参考"
                    )
                )
            }
        }

        for group in SourceModuleConnectionProjection(workspace: session.workspace).groups {
            guard let generatorNode = nodesByEntityID[group.generatorID.rawValue]?.first,
                  let sourceNode = CanvasReferenceSourceNodeResolver.resolve(
                      assetID: group.assetID,
                      preferredNodeID: nil,
                      among: nodesByEntityID[group.assetID.rawValue] ?? []
                  ),
                  let sourceAsset = session.asset(for: group.assetID) else {
                continue
            }
            let sourceLayout = imageLayout(for: sourceNode, asset: sourceAsset)
            let targetMediaKind = session.generator(for: group.generatorID)?.mediaKind
            result.append(
                ConnectionSegment(
                    id: .sourceModuleGroup(group.id),
                    selectionID: .sourceModuleGroup(group.id),
                    style: .promptBundle,
                    start: sourceLayout.trailingImageConnectionAnchor,
                    end: WorldPoint(
                        x: generatorNode.frame.minX,
                        y: generatorNode.frame.minY + GeneratorNodeLayoutPolicy.inputAnchorY
                    ),
                    promptModuleIDs: group.moduleIDs,
                    sourceTitle: "\(group.count) 项结构化提示词",
                    targetTitle: targetMediaKind == .video ? "视频生成" : "图片生成"
                )
            )
        }

        for module in session.workspace.promptModules {
            guard let sourceAssetID = module.sourceAssetID,
                  let sourceAsset = session.asset(for: sourceAssetID),
                  let moduleNode = nodesByEntityID[module.id.rawValue]?.first,
                  let sourceNode = CanvasReferenceSourceNodeResolver.resolve(
                      assetID: sourceAssetID,
                      preferredNodeID: nil,
                      among: nodesByEntityID[sourceAssetID.rawValue] ?? []
                  ) else { continue }
            let sourceLayout = imageLayout(for: sourceNode, asset: sourceAsset)
            result.append(
                ConnectionSegment(
                    id: .moduleSource(
                        moduleID: module.id,
                        assetID: sourceAssetID
                    ),
                    style: .lineage,
                    start: sourceLayout.trailingImageConnectionAnchor,
                    end: WorldPoint(
                        x: moduleNode.frame.minX,
                        y: moduleNode.frame.minY + moduleNode.frame.height / 2
                    ),
                    sourceTitle: sourceAsset.displayName,
                    targetTitle: promptModuleTitle(module.id)
                )
            )
        }

        let groupedNodeIDs = Set(session.workspace.generationGroups.flatMap(\.memberNodeIDs))
        for group in session.workspace.generationGroups {
            guard let generatorID = group.generatorID,
                  let generatorNodes = nodesByEntityID[generatorID.rawValue] else { continue }
            let layout = session.generationGroupLayout(for: group)
            let groupBounds = nodeDrag?.frame(
                forGenerationGroup: group.id,
                frame: layout.bounds,
                viewportScale: viewport.scale
            ) ?? layout.bounds
            guard let generatorNode = closestNode(to: groupBounds, among: generatorNodes) else { continue }
            result.append(
                ConnectionSegment(
                    id: .generationGroup(group.id),
                    style: .lineage,
                    start: WorldPoint(
                        x: generatorNode.frame.maxX,
                        y: generatorNode.frame.minY + generatorNode.frame.height / 2
                    ),
                    end: WorldPoint(
                        x: groupBounds.minX,
                        y: groupBounds.minY + min(layout.headerFrame.height, groupBounds.height) / 2
                            + max(0, layout.headerFrame.minY - layout.bounds.minY)
                    ),
                    sourceTitle: session.generator(for: generatorID)?.name ?? "生图节点",
                    targetTitle: WorkspaceDisplayNamePolicy.normalized(group.name ?? "").isEmpty
                        ? "生成结果"
                        : WorkspaceDisplayNamePolicy.normalized(group.name ?? "")
                )
            )
        }

        for asset in session.workspace.assets {
            guard asset.isResult,
                  let generationID = asset.sourceGenerationID,
                  let generation = session.workspace.generations.first(where: { $0.id == generationID }),
                  let generatorID = generation.generatorID,
                  let generatorNodes = nodesByEntityID[generatorID.rawValue],
                  let assetNodes = nodesByEntityID[asset.id.rawValue] else { continue }
            for assetNode in assetNodes where !groupedNodeIDs.contains(assetNode.id) {
                guard let generatorNode = closestNode(to: assetNode, among: generatorNodes) else { continue }
                let assetLayout = imageLayout(for: assetNode, asset: asset)
                result.append(
                    ConnectionSegment(
                        id: .generationOutput(
                            generationID: generation.id,
                            assetID: asset.id,
                            targetNodeID: assetNode.id
                        ),
                        style: .lineage,
                        start: WorldPoint(
                            x: generatorNode.frame.maxX,
                            y: generatorNode.frame.minY + generatorNode.frame.height / 2
                        ),
                        end: assetLayout.leadingImageConnectionAnchor,
                        sourceTitle: session.generator(for: generatorID)?.name ?? "生图节点",
                        targetTitle: asset.displayName
                    )
                )
            }
        }
        return result
    }

    private func embeddedOutputGeneratorNode(
        for asset: Asset,
        nodesByEntityID: [UUID: [CanvasNode]]
    ) -> CanvasNode? {
        guard let generationID = asset.sourceGenerationID,
              let generation = session.workspace.generations.first(where: { $0.id == generationID }),
              let sourceGeneratorID = generation.generatorID else {
            return nil
        }
        return nodesByEntityID[sourceGeneratorID.rawValue]?.first
    }

    private func displayedOutputAsset(for generatorNode: CanvasNode) -> Asset? {
        guard let generatorID = generatorNode.generatorID else { return nil }
        let batches = session.generationOutputBatches(for: generatorID)
        let assets = batches.flatMap(\.assets)
        if let selectedAssetID = generatorOutputSelections[generatorID],
           let selectedAsset = assets.first(where: { $0.id == selectedAssetID }) {
            return selectedAsset
        }
        return batches.last?.assets.first
    }

    private func closestNode(to anchor: CanvasNode, among candidates: [CanvasNode]) -> CanvasNode? {
        let anchorX = anchor.frame.minX + anchor.frame.width / 2
        let anchorY = anchor.frame.minY + anchor.frame.height / 2
        return candidates.min { lhs, rhs in
            let lhsX = lhs.frame.minX + lhs.frame.width / 2
            let lhsY = lhs.frame.minY + lhs.frame.height / 2
            let rhsX = rhs.frame.minX + rhs.frame.width / 2
            let rhsY = rhs.frame.minY + rhs.frame.height / 2
            let lhsDistance = pow(lhsX - anchorX, 2) + pow(lhsY - anchorY, 2)
            let rhsDistance = pow(rhsX - anchorX, 2) + pow(rhsY - anchorY, 2)
            return lhsDistance < rhsDistance
        }
    }

    private func closestNode(to anchorFrame: WorldRect, among candidates: [CanvasNode]) -> CanvasNode? {
        let anchorX = anchorFrame.minX + anchorFrame.width / 2
        let anchorY = anchorFrame.minY + anchorFrame.height / 2
        return candidates.min { lhs, rhs in
            let lhsX = lhs.frame.minX + lhs.frame.width / 2
            let lhsY = lhs.frame.minY + lhs.frame.height / 2
            let rhsX = rhs.frame.minX + rhs.frame.width / 2
            let rhsY = rhs.frame.minY + rhs.frame.height / 2
            let lhsDistance = pow(lhsX - anchorX, 2) + pow(lhsY - anchorY, 2)
            let rhsDistance = pow(rhsX - anchorX, 2) + pow(rhsY - anchorY, 2)
            return lhsDistance < rhsDistance
        }
    }

    private func imageLayout(for node: CanvasNode, asset: Asset) -> ImageNodeSurroundLayout {
        return ImageNodeSurroundLayout(
            imageFrame: node.frame,
            contentAspectRatio: asset.contentAspectRatio,
            includesHeaderChrome: asset.supportsReversePrompt,
            includesAnalysisChrome: asset.supportsReversePrompt
        )
    }

    private func promptModuleTitle(_ moduleID: PromptModuleID) -> String {
        guard let module = session.promptModule(for: moduleID) else { return "提示词" }
        switch module.role {
        case .visual(let category):
            return category.displayName
        case .instruction:
            return "创作指令"
        }
    }

    private func segmentColor(
        for style: CanvasConnectionVisualStyle,
        emphasized: Bool
    ) -> Color {
        switch style {
        case .prompt:
            return Color.accentColor.opacity(emphasized ? 0.96 : 0.5)
        case .promptBundle:
            return Color.indigo.opacity(emphasized ? 0.96 : 0.74)
        case .reference:
            return Color.accentColor.opacity(emphasized ? 0.96 : 0.68)
        case .lineage:
            return Color.secondary.opacity(0.24)
        }
    }
}

private enum CanvasConnectionSelectionID: Hashable {
    case recipeBinding(
        generatorID: GeneratorID,
        recipeID: RecipeID,
        bindingID: RecipeBindingID
    )
    case sourceModuleGroup(SourceModuleConnectionGroupID)
    case assetReference(generatorID: GeneratorID, assetID: AssetID)
}

private enum CanvasConnectionSegmentID: Hashable {
    case recipeBinding(
        generatorID: GeneratorID,
        recipeID: RecipeID,
        bindingID: RecipeBindingID
    )
    case sourceModuleGroup(SourceModuleConnectionGroupID)
    case assetReference(generatorID: GeneratorID, assetID: AssetID)
    case moduleSource(moduleID: PromptModuleID, assetID: AssetID)
    case generationGroup(CanvasGenerationGroupID)
    case generationOutput(
        generationID: GenerationID,
        assetID: AssetID,
        targetNodeID: CanvasNodeID
    )
}

private enum CanvasConnectionVisualStyle {
    case prompt
    case promptBundle
    case reference
    case lineage

    var lineWidth: CGFloat {
        switch self {
        case .prompt:
            2
        case .promptBundle:
            2.4
        case .reference:
            2.2
        case .lineage:
            1.6
        }
    }
}

private struct ConnectionSegment: Identifiable {
    let id: CanvasConnectionSegmentID
    let selectionID: CanvasConnectionSelectionID?
    let style: CanvasConnectionVisualStyle
    let start: WorldPoint
    let end: WorldPoint
    let promptModuleIDs: [PromptModuleID]
    let sourceTitle: String
    let targetTitle: String

    init(
        id: CanvasConnectionSegmentID,
        selectionID: CanvasConnectionSelectionID? = nil,
        style: CanvasConnectionVisualStyle,
        start: WorldPoint,
        end: WorldPoint,
        promptModuleIDs: [PromptModuleID] = [],
        sourceTitle: String,
        targetTitle: String
    ) {
        self.id = id
        self.selectionID = selectionID
        self.style = style
        self.start = start
        self.end = end
        self.promptModuleIDs = promptModuleIDs
        self.sourceTitle = sourceTitle
        self.targetTitle = targetTitle
    }

    var isEditable: Bool { selectionID != nil }
    var promptModuleCount: Int? {
        promptModuleIDs.isEmpty ? nil : promptModuleIDs.count
    }
}

private struct CanvasConnectionViewGeometry {
    let start: CGPoint
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint

    init(segment: ConnectionSegment, viewport: ViewportTransform) {
        let startPoint = viewport.viewPoint(for: segment.start)
        let endPoint = viewport.viewPoint(for: segment.end)
        start = CGPoint(x: startPoint.x, y: startPoint.y)
        end = CGPoint(x: endPoint.x, y: endPoint.y)
        let horizontalDistance = max(48, abs(end.x - start.x) * 0.45)
        control1 = CGPoint(
            x: start.x + horizontalDistance,
            y: start.y
        )
        control2 = CGPoint(
            x: end.x - horizontalDistance,
            y: end.y
        )
    }

    var path: Path {
        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: control1,
            control2: control2
        )
        return path
    }

    func point(at progress: CGFloat) -> CGPoint {
        let t = min(1, max(0, progress))
        let inverse = 1 - t
        let startWeight = inverse * inverse * inverse
        let firstControlWeight = 3 * inverse * inverse * t
        let secondControlWeight = 3 * inverse * t * t
        let endWeight = t * t * t
        return CGPoint(
            x: start.x * startWeight
                + control1.x * firstControlWeight
                + control2.x * secondControlWeight
                + end.x * endWeight,
            y: start.y * startWeight
                + control1.y * firstControlWeight
                + control2.y * secondControlWeight
                + end.y * endWeight
        )
    }
}

private struct CanvasConnectionInteractionView: View {
    let session: WorkspaceSession
    let segment: ConnectionSegment
    let viewport: ViewportTransform
    @Binding var selectedConnectionID: CanvasConnectionSelectionID?
    @Binding var hoveredConnectionID: CanvasConnectionSelectionID?
    let isInteractionSuppressed: Bool
    let onDisconnect: (CanvasConnectionSelectionID) -> Void
    let onDisconnectSourceModules: (
        SourceModuleConnectionGroupID,
        [PromptModuleID]
    ) -> Void

    @State private var isBundlePopoverPresented = false
    @State private var isDisconnectButtonHovered = false

    var body: some View {
        let geometry = CanvasConnectionViewGeometry(
            segment: segment,
            viewport: viewport
        )
        let hitPath = geometry.path.strokedPath(
            StrokeStyle(lineWidth: 16, lineCap: .round)
        )

        ZStack {
            hitPath
                .fill(Color.primary.opacity(0.001))
                .contentShape(hitPath)
                .onTapGesture {
                    selectConnection()
                }
                .onHover { isHovering in
                    guard let selectionID = segment.selectionID else { return }
                    if isHovering {
                        hoveredConnectionID = selectionID
                    } else if hoveredConnectionID == selectionID {
                        hoveredConnectionID = nil
                    }
                }
                .contextMenu {
                    disconnectContextMenu
                }
                .accessibilityElement()
                .accessibilityLabel(
                    "\(segment.sourceTitle)到\(segment.targetTitle)的连接"
                )
                .accessibilityHint("单击选择，按 Delete 断开连接")
                .accessibilityAddTraits(
                    selectedConnectionID == segment.selectionID ? .isSelected : []
                )
                .accessibilityAction(named: "断开连接") {
                    disconnectAll()
                }

            if selectedConnectionID == segment.selectionID {
                Button {
                    disconnectAll()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            isDisconnectButtonHovered
                                ? Color.red
                                : Color.secondary
                        )
                        .frame(width: 28, height: 28)
                        .background {
                            ZStack {
                                Circle()
                                    .fill(.regularMaterial)
                                Circle()
                                    .fill(
                                        isDisconnectButtonHovered
                                            ? Color.red.opacity(0.05)
                                            : Color.clear
                                    )
                            }
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    isDisconnectButtonHovered
                                        ? Color.red.opacity(0.36)
                                        : Color.secondary.opacity(0.22),
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color: Color.black.opacity(0.10),
                            radius: 4,
                            y: 2
                        )
                }
                .buttonStyle(.plain)
                .help(disconnectButtonTitle)
                .accessibilityLabel(disconnectButtonTitle)
                .onHover { isHovering in
                    isDisconnectButtonHovered = isHovering
                }
                .animation(
                    .easeOut(duration: 0.12),
                    value: isDisconnectButtonHovered
                )
                .position(geometry.point(at: 0.5))
            }

            if let count = segment.promptModuleCount,
               case .sourceModuleGroup = segment.selectionID {
                Button {
                    selectConnection()
                    isBundlePopoverPresented = true
                } label: {
                    Text("\(count)")
                        .font(.system(size: 9 * viewport.scale, weight: .bold))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                        .frame(
                            width: max(16, 20 * viewport.scale),
                            height: max(16, 20 * viewport.scale)
                        )
                        .background(Color.indigo, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.72),
                                    lineWidth: max(0.5, viewport.scale)
                                )
                        }
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("查看并管理 \(count) 项结构化提示词")
                .position(geometry.point(at: 0.34))
                .popover(
                    isPresented: $isBundlePopoverPresented,
                    arrowEdge: .bottom
                ) {
                    bundlePopover
                }
            }
        }
        .allowsHitTesting(!isInteractionSuppressed)
        .onDisappear {
            guard hoveredConnectionID == segment.selectionID else { return }
            hoveredConnectionID = nil
        }
    }

    private var disconnectButtonTitle: String {
        if let count = segment.promptModuleCount {
            return "断开 \(count) 项"
        }
        return "断开"
    }

    @ViewBuilder
    private var disconnectContextMenu: some View {
        if let groupID = sourceModuleGroupID {
            if segment.promptModuleIDs.count > 1 {
                Menu("断开其中一项", systemImage: "list.bullet") {
                    ForEach(segment.promptModuleIDs, id: \.self) { moduleID in
                        Button(moduleTitle(moduleID)) {
                            onDisconnectSourceModules(groupID, [moduleID])
                        }
                    }
                }
            }
            Button(
                "断开全部 \(segment.promptModuleIDs.count) 项",
                systemImage: "link.badge.minus",
                role: .destructive
            ) {
                disconnectAll()
            }
        } else {
            Button(
                "断开连接",
                systemImage: "link.badge.minus",
                role: .destructive
            ) {
                disconnectAll()
            }
        }
    }

    private var bundlePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已连接的结构化提示词")
                        .font(.headline)
                    Text("连接到 \(segment.targetTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text("\(segment.promptModuleIDs.count) 项")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(segment.promptModuleIDs, id: \.self) { moduleID in
                Button {
                    isBundlePopoverPresented = false
                    guard let groupID = sourceModuleGroupID else { return }
                    onDisconnectSourceModules(groupID, [moduleID])
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.quote")
                            .foregroundStyle(Color.indigo)
                        Text(moduleTitle(moduleID))
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Color.red)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button(role: .destructive) {
                isBundlePopoverPresented = false
                disconnectAll()
            } label: {
                Label(
                    "断开全部 \(segment.promptModuleIDs.count) 项",
                    systemImage: "link.badge.minus"
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 310)
    }

    private var sourceModuleGroupID: SourceModuleConnectionGroupID? {
        guard case let .sourceModuleGroup(groupID) = segment.selectionID else {
            return nil
        }
        return groupID
    }

    private func selectConnection() {
        guard let selectionID = segment.selectionID else { return }
        session.clearSelection()
        selectedConnectionID = selectionID
    }

    private func disconnectAll() {
        guard let selectionID = segment.selectionID else { return }
        if let groupID = sourceModuleGroupID {
            onDisconnectSourceModules(groupID, segment.promptModuleIDs)
        } else {
            onDisconnect(selectionID)
        }
    }

    private func moduleTitle(_ moduleID: PromptModuleID) -> String {
        guard let module = session.promptModule(for: moduleID) else {
            return "提示词"
        }
        let roleTitle: String
        switch module.role {
        case .visual(let category):
            roleTitle = category.displayName
        case .instruction:
            roleTitle = "创作指令"
        }
        let content = module.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return roleTitle }
        return "\(roleTitle) · \(String(content.prefix(26)))"
    }
}

/// Image pixels keep their persisted canvas frame. Lightweight metadata rails
/// are rendered immediately outside that frame so they never cover the image
/// or shift connection anchors.
private enum ImageCanvasChrome {
    static let topRailHeight = ImageNodeSurroundLayout.defaultTopRailHeight
    static let bottomRailHeight = ImageNodeSurroundLayout.defaultSummaryHeight
    static let railGap = ImageNodeSurroundLayout.defaultRailGap

    static func shellFrame(
        around imageFrame: WorldRect,
        includesHeaderChrome: Bool,
        includesAnalysisChrome: Bool,
        includesStructuredPromptChrome: Bool
    ) -> WorldRect {
        ImageNodeSurroundLayout(
            imageFrame: imageFrame,
            contentAspectRatio: nil,
            includesHeaderChrome: includesHeaderChrome,
            includesAnalysisChrome: includesAnalysisChrome,
            includesStructuredPromptChrome: includesStructuredPromptChrome
        ).shellFrame
    }
}

private enum VideoCanvasChrome {
    static let controlRailHeight = 36.0
    static let controlRailGap = 8.0

    static func controlFrame(below videoFrame: WorldRect) -> WorldRect {
        WorldRect(
            x: videoFrame.minX,
            y: videoFrame.maxY + controlRailGap,
            width: videoFrame.width,
            height: controlRailHeight
        )
    }

    static func shellFrame(around videoFrame: WorldRect, showsControls: Bool) -> WorldRect {
        let base = ImageNodeSurroundLayout(
            imageFrame: videoFrame,
            contentAspectRatio: nil,
            includesHeaderChrome: true,
            includesAnalysisChrome: false
        ).shellFrame
        guard showsControls else { return base }
        let controls = controlFrame(below: videoFrame)
        return WorldRect(
            x: min(base.minX, controls.minX),
            y: min(base.minY, controls.minY),
            width: max(base.maxX, controls.maxX) - min(base.minX, controls.minX),
            height: max(base.maxY, controls.maxY) - min(base.minY, controls.minY)
        )
    }
}

private struct VideoCanvasNodeView: View {
    let session: WorkspaceSession
    let node: CanvasNode
    let asset: Asset
    let scale: Double
    let viewport: ViewportTransform
    @Binding var activeDrag: CanvasNodeDragState?
    let showsReferenceDragHandle: Bool
    let isNodeDragSuppressed: Bool
    let onReferenceDragChanged: (CGPoint, CGPoint) -> Void
    let onReferenceDragEnded: (CGPoint) -> Void
    @State private var playback = VideoPlaybackController()
    @State private var isMediaHovering = false
    @State private var isReferenceHandleDragging = false
    @State private var mediaHoverExitTask: Task<Void, Never>?

    var body: some View {
        let layout = ImageNodeSurroundLayout(
            imageFrame: node.frame,
            contentAspectRatio: nil,
            includesHeaderChrome: true,
            includesAnalysisChrome: false
        )
        let showsControls = (
            session.selectedNodeID == node.id
                || session.activeVideoNodeID == node.id
        ) && scale >= 0.5
        let controlFrame = VideoCanvasChrome.controlFrame(below: node.frame)
        let shellFrame = VideoCanvasChrome.shellFrame(
            around: node.frame,
            showsControls: showsControls
        )

        ZStack(alignment: .topLeading) {
            header
                .frame(
                    width: layout.headerFrame.width * scale,
                    height: layout.headerFrame.height * scale
                )
                .offset(offset(for: layout.headerFrame, in: shellFrame))

            videoSurface
                .frame(
                    width: layout.displayedImageFrame.width * scale,
                    height: layout.displayedImageFrame.height * scale
                )
                .offset(offset(for: layout.displayedImageFrame, in: shellFrame))

            if showsControls {
                VideoPlaybackControlRail(
                    controller: playback,
                    scale: scale,
                    onTogglePlayback: togglePlayback
                )
                .frame(
                    width: controlFrame.width * scale,
                    height: controlFrame.height * scale
                )
                .offset(offset(for: controlFrame, in: shellFrame))
            }
        }
        .frame(
            width: shellFrame.width * scale,
            height: shellFrame.height * scale,
            alignment: .topLeading
        )
        .offset(activeDrag?.offset(for: node.id) ?? .zero)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("视频素材 \(asset.displayName)")
        .accessibilityAddTraits(session.isNodeSelected(node.id) ? .isSelected : [])
        .onChange(of: session.activeVideoNodeID) { _, activeNodeID in
            if activeNodeID != node.id, playback.player != nil {
                playback.stopAndRelease()
            }
        }
        .onDisappear {
            mediaHoverExitTask?.cancel()
            playback.stopAndRelease()
            if session.activeVideoNodeID == node.id {
                session.activeVideoNodeID = nil
            }
        }
    }

    private var header: some View {
        Group {
            if scale >= 0.5 {
                HStack(spacing: 6 * scale) {
                    Text(asset.displayName)
                        .font(.system(size: 11 * scale, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if scale >= 0.72 {
                        Label("视频", systemImage: "film")
                            .font(.system(size: 10 * scale, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 8 * scale, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 3 * scale)
            } else {
                Color.clear
            }
        }
    }

    private var videoSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(Color.secondary.opacity(0.1))

            LocalVideoRenderView(controller: playback, scale: scale)
        }
        .contentShape(Rectangle())
        .onHover(perform: updateMediaHover)
        .onTapGesture {
            session.select(node.id, extending: NSEvent.modifierFlags.contains(.shift))
        }
        .contextMenu {
            let removalPresentation = CanvasRemovalPresentation(
                session: session,
                contextualNodeID: node.id
            )
            Button(playback.isPlaying ? "暂停" : "播放", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") {
                if !session.isNodeSelected(node.id) { session.select(node.id) }
                togglePlayback()
            }
            Divider()
            Button("在 Finder 中显示", systemImage: "folder") {
                session.revealAssetInFinder(asset.id)
            }
            Divider()
            Button(
                removalPresentation.title,
                systemImage: removalPresentation.systemImage,
                role: .destructive
            ) {
                if !session.isNodeSelected(node.id) { session.select(node.id) }
                session.removeSelectedNodesFromCanvas()
            }
            .help(removalPresentation.help)
        }
        .modifier(
            CanvasNodeDragModifier(
                session: session,
                node: node,
                viewport: viewport,
                activeDrag: $activeDrag,
                isDragSuppressed: isNodeDragSuppressed,
                appliesOffset: false
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .stroke(
                    CanvasNodeSelectionAppearance.strokeColor(
                        isPrimary: session.selectedNodeID == node.id,
                        isSelected: session.isNodeSelected(node.id)
                    ),
                    lineWidth: CanvasNodeSelectionAppearance.lineWidth(
                        isPrimary: session.selectedNodeID == node.id,
                        isSelected: session.isNodeSelected(node.id),
                        scale: scale
                    )
                )
        }
        .overlay(alignment: .trailing) {
            if showsReferenceDragHandle,
               isMediaHovering || isReferenceHandleDragging {
                MediaReferenceDragHandle(
                    mediaKind: .video,
                    scale: scale,
                    coordinateSpaceName: CanvasCoordinateSpace.name,
                    onDragActivityChanged: updateReferenceHandleActivity,
                    onDragChanged: onReferenceDragChanged,
                    onDragEnded: onReferenceDragEnded
                )
                .offset(x: MediaReferenceDragHandle.outsideOffset(scale: scale))
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isMediaHovering)
        .shadow(color: .black.opacity(0.08), radius: 8 * scale, y: 3 * scale)
    }

    private func togglePlayback() {
        if playback.isPlaying {
            playback.pause()
            if session.activeVideoNodeID == node.id {
                session.activeVideoNodeID = nil
            }
            return
        }
        session.activeVideoNodeID = node.id
        Task {
            await playback.toggle {
                try await session.resolvedAssetURL(for: asset)
            }
            if !playback.isPlaying, session.activeVideoNodeID == node.id {
                session.activeVideoNodeID = nil
            }
        }
    }

    private func updateMediaHover(_ hovering: Bool) {
        mediaHoverExitTask?.cancel()
        if hovering {
            isMediaHovering = true
            return
        }
        mediaHoverExitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isReferenceHandleDragging else { return }
            isMediaHovering = false
        }
    }

    private func updateReferenceHandleActivity(_ active: Bool) {
        isReferenceHandleDragging = active
        if active {
            mediaHoverExitTask?.cancel()
            isMediaHovering = true
        } else {
            updateMediaHover(false)
        }
    }

    private func offset(for frame: WorldRect, in shellFrame: WorldRect) -> CGSize {
        CGSize(
            width: (frame.minX - shellFrame.minX) * scale,
            height: (frame.minY - shellFrame.minY) * scale
        )
    }
}

private struct ImageCanvasNodeView: View {
    let session: WorkspaceSession
    let node: CanvasNode
    let asset: Asset
    let scale: Double
    let viewport: ViewportTransform
    @Binding var activeDrag: CanvasNodeDragState?
    let selectedPromptModuleIDs: Set<PromptModuleID>
    let showsReferenceDragHandle: Bool
    let isNodeDragSuppressed: Bool
    let onChromeActivityChanged: (Bool) -> Void
    let onPromptTagDragChanged: (
        PromptModule,
        PromptModuleCategory,
        CGPoint,
        CGPoint
    ) -> Void
    let onPromptTagDragEnded: (PromptModule, PromptModuleCategory, CGPoint) -> Void
    let onPromptSelectionToggle: (PromptModuleID) -> Void
    let onReferenceDragChanged: (CGPoint, CGPoint) -> Void
    let onReferenceDragEnded: (CGPoint) -> Void
    let onPromptBundleDragChanged: ([PromptModuleID], CGPoint, CGPoint) -> Void
    let onPromptBundleDragEnded: ([PromptModuleID], CGPoint) -> Void

    @State private var image: NSImage?
    @State private var isMediaHovering = false
    @State private var isReferenceHandleDragging = false
    @State private var mediaHoverExitTask: Task<Void, Never>?

    var body: some View {
        let layout = ImageNodeSurroundLayout(
            imageFrame: node.frame,
            contentAspectRatio: contentAspectRatio,
            includesHeaderChrome: showsReferenceHeader,
            includesAnalysisChrome: showsAnalysisChrome,
            includesStructuredPromptChrome: hasCompletedAnalysis
        )
        let shellFrame = layout.shellFrame

        ZStack(alignment: .topLeading) {
            if showsReferenceHeader {
                imageHeaderRail
                    .frame(
                        width: layout.headerFrame.width * scale,
                        height: layout.headerFrame.height * scale
                    )
                    .offset(offset(for: layout.headerFrame, in: shellFrame))
            }

            interactiveImageSurface
                .frame(
                    width: layout.displayedImageFrame.width * scale,
                    height: layout.displayedImageFrame.height * scale
                )
                .offset(offset(for: layout.displayedImageFrame, in: shellFrame))
                .zIndex(isMediaHovering || isReferenceHandleDragging ? 30 : 0)

            if showsAnalysisChrome {
                ImageAnalysisSummaryView(
                    phase: analysisPhase,
                    scale: scale,
                    isVisible: session.isNodeSelected(node.id),
                    onRetry: { session.startAnalysis(assetID: asset.id) },
                    onCancel: { session.cancelAnalysis(assetID: asset.id) },
                    onHoverChanged: { hovering in
                        if hovering { onChromeActivityChanged(true) }
                    }
                )
                .frame(
                    width: layout.summaryFrame.width * scale,
                    height: layout.summaryFrame.height * scale
                )
                .offset(offset(for: layout.summaryFrame, in: shellFrame))

                if hasCompletedAnalysis {
                    ImageStructuredPromptTagsView(
                        modules: analysisModules,
                        scale: scale,
                        isVisible: session.isNodeSelected(node.id),
                        coordinateSpaceName: CanvasCoordinateSpace.name,
                        selectedModuleIDs: selectedPromptModuleIDs,
                        onHoverChanged: { hovering in
                            if hovering { onChromeActivityChanged(true) }
                        },
                        onSelectionToggle: onPromptSelectionToggle,
                        onDragChanged: onPromptTagDragChanged,
                        onDragEnded: onPromptTagDragEnded,
                        onBundleDragChanged: onPromptBundleDragChanged,
                        onBundleDragEnded: onPromptBundleDragEnded
                    )
                    .frame(
                        width: layout.tagLaneFrame.width * scale,
                        height: layout.tagLaneFrame.height * scale,
                        alignment: .topLeading
                    )
                    .offset(offset(for: layout.tagLaneFrame, in: shellFrame))
                }
            }
        }
        .frame(
            width: shellFrame.width * scale,
            height: shellFrame.height * scale,
            alignment: .topLeading
        )
        .offset(activeDrag?.offset(for: node.id) ?? .zero)
        .task(id: asset.relativePath) {
            let url = session.assetURL(for: asset)
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            image = data.flatMap(NSImage.init(data:))
        }
        .onDisappear {
            mediaHoverExitTask?.cancel()
            onChromeActivityChanged(false)
        }
        .onChange(of: session.selectedNodeIDs, initial: true) { _, selectedNodeIDs in
            onChromeActivityChanged(selectedNodeIDs.contains(node.id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("图片素材 \(asset.displayName)")
        .accessibilityAddTraits(session.isNodeSelected(node.id) ? .isSelected : [])
    }

    private var interactiveImageSurface: some View {
        imageSurface
            .contentShape(Rectangle())
            .onHover(perform: updateMediaHover)
            .onTapGesture {
                session.select(node.id, extending: NSEvent.modifierFlags.contains(.shift))
            }
            .contextMenu { imageContextMenu }
            .modifier(
                CanvasNodeDragModifier(
                    session: session,
                    node: node,
                    viewport: viewport,
                    activeDrag: $activeDrag,
                    isDragSuppressed: isNodeDragSuppressed,
                    appliesOffset: false
                )
            )
            .overlay(alignment: .trailing) {
                if showsReferenceDragHandle,
                   isMediaHovering || isReferenceHandleDragging {
                    MediaReferenceDragHandle(
                        mediaKind: .image,
                        scale: scale,
                        coordinateSpaceName: CanvasCoordinateSpace.name,
                        onDragActivityChanged: updateReferenceHandleActivity,
                        onDragChanged: onReferenceDragChanged,
                        onDragEnded: onReferenceDragEnded
                    )
                    .offset(x: MediaReferenceDragHandle.outsideOffset(scale: scale))
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
                }
            }
            .animation(.easeOut(duration: 0.12), value: isMediaHovering)
    }

    private func updateMediaHover(_ hovering: Bool) {
        mediaHoverExitTask?.cancel()
        if hovering {
            isMediaHovering = true
            return
        }
        mediaHoverExitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isReferenceHandleDragging else { return }
            isMediaHovering = false
        }
    }

    private func updateReferenceHandleActivity(_ active: Bool) {
        isReferenceHandleDragging = active
        if active {
            mediaHoverExitTask?.cancel()
            isMediaHovering = true
        } else {
            updateMediaHover(false)
        }
    }

    @ViewBuilder
    private var imageContextMenu: some View {
        let removalPresentation = CanvasRemovalPresentation(
            session: session,
            contextualNodeID: node.id
        )
        Button("局部改图…", systemImage: "paintbrush.pointed") {
            session.presentMaskEditor(sourceAssetID: asset.id)
        }
        .help("画出需要修改的区域，并创建新的局部改图节点（Beta）")

        Divider()
        if showsAnalysisChrome {
            if session.isAnalyzing(asset.id) {
                Button("取消分析", systemImage: "stop.circle", role: .cancel) {
                    session.cancelAnalysis(assetID: asset.id)
                }
            } else {
                Button(
                    analysisModules.isEmpty ? "分析图片" : "重新分析",
                    systemImage: "viewfinder"
                ) {
                    session.startAnalysis(assetID: asset.id)
                }
            }
        }

        if showsAnalysisChrome,
           analysisModules.contains(where: { session.isPromptModuleOnCanvas($0.id) }) {
            Button("收起已展开的结构化提示词", systemImage: "rectangle.compress.vertical") {
                session.collapseAnalysisModuleNodes(for: asset.id)
            }
        }

        if showsAnalysisChrome {
            Divider()
        }
        if asset.kind == .generated {
            Button("作为普通图片使用", systemImage: "photo.badge.plus") {
                session.extractGeneratedResultAsSource(nodeID: node.id)
            }
            .help("创建可分析和复用的普通图片实例；保留原生成记录和来源关系")
        }
        Button("在 Finder 中显示", systemImage: "folder") {
            session.revealAssetInFinder(asset.id)
        }
        Button(
            removalPresentation.title,
            systemImage: removalPresentation.systemImage,
            role: .destructive
        ) {
            if !session.isNodeSelected(node.id) { session.select(node.id) }
            session.removeSelectedNodesFromCanvas()
        }
        .help(removalPresentation.help)
    }

    @ViewBuilder
    private var imageHeaderRail: some View {
        HStack(spacing: 6 * scale) {
            Text(asset.displayName)
                .font(.system(size: 11 * scale, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if scale >= 0.72 {
                Label("图片", systemImage: "photo")
                    .font(.system(size: 10 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 8 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }

        }
        .padding(.horizontal, 3 * scale)
    }

    private var imageSurface: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .stroke(
                    CanvasNodeSelectionAppearance.strokeColor(
                        isPrimary: session.selectedNodeID == node.id,
                        isSelected: session.isNodeSelected(node.id)
                    ),
                    lineWidth: CanvasNodeSelectionAppearance.lineWidth(
                        isPrimary: session.selectedNodeID == node.id,
                        isSelected: session.isNodeSelected(node.id),
                        scale: scale
                    )
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 8 * scale, y: 3 * scale)
    }

    private var analysisModules: [PromptModule] {
        session.analysisModules(for: asset.id)
    }

    private var hasCompletedAnalysis: Bool {
        session.latestAnalysisSnapshot(for: asset.id) != nil
            && !analysisModules.isEmpty
            && !session.isAnalyzing(asset.id)
            && asset.state != .failed
    }

    private var showsAnalysisChrome: Bool {
        asset.supportsReversePrompt
    }

    private var showsReferenceHeader: Bool {
        asset.supportsReversePrompt
    }

    private var analysisPhase: ImageAnalysisSummaryView.Phase {
        if session.isAnalyzing(asset.id) {
            return .analyzing
        }
        if asset.state == .failed {
            return .failed(message: "上次分析没有完成，请重新分析。")
        }
        if hasCompletedAnalysis {
            return .result(
                summary: session.analysisSummary(for: asset.id) ?? "",
                modules: analysisModules
            )
        }
        return .empty
    }

    private var contentAspectRatio: Double? {
        asset.contentAspectRatio
    }

    private func offset(for frame: WorldRect, in shellFrame: WorldRect) -> CGSize {
        CGSize(
            width: (frame.minX - shellFrame.minX) * scale,
            height: (frame.minY - shellFrame.minY) * scale
        )
    }

    private func referenceRoleTitle(_ role: GeneratorAssetRole) -> String {
        switch role {
        case .general: "整体参考"
        case .identity: "主体身份"
        case .environment: "场景环境"
        case .style: "风格"
        case .composition: "构图"
        case .palette: "色彩"
        case .structure: "结构"
        }
    }
}

private struct CanvasGridView: View {
    let viewport: ViewportTransform

    var body: some View {
        Canvas { context, size in
            let baseSpacing = 32.0
            let scaledSpacing = baseSpacing * viewport.scale
            guard scaledSpacing >= 4 else { return }

            let xOffset = viewport.translation.x.truncatingRemainder(dividingBy: scaledSpacing)
            let yOffset = viewport.translation.y.truncatingRemainder(dividingBy: scaledSpacing)
            let dotRadius = min(1.1, max(0.55, 0.72 * sqrt(viewport.scale)))
            var dots = Path()

            for x in stride(
                from: xOffset - scaledSpacing,
                through: Double(size.width) + scaledSpacing,
                by: scaledSpacing
            ) {
                for y in stride(
                    from: yOffset - scaledSpacing,
                    through: Double(size.height) + scaledSpacing,
                    by: scaledSpacing
                ) {
                    dots.addEllipse(
                        in: CGRect(
                            x: x - dotRadius,
                            y: y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )
                    )
                }
            }

            context.fill(dots, with: .color(.secondary.opacity(0.16)))
        }
        .accessibilityHidden(true)
    }
}

private struct CanvasControlsView: View {
    let session: WorkspaceSession
    let viewportSize: ViewSize

    var body: some View {
        HStack(spacing: 8) {
            Button {
                session.zoom(by: 0.8, viewportSize: viewportSize)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("缩小")

            Text("\(Int((session.viewport.scale * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44)

            Button {
                session.zoom(by: 1.25, viewportSize: viewportSize)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("放大")

            Divider()
                .frame(height: 16)

            Button {
                session.resetViewport(viewportSize: viewportSize)
            } label: {
                Label("重置", systemImage: "scope")
            }
            .help("重置画布视图")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.quaternary, lineWidth: 1)
        }
    }
}
