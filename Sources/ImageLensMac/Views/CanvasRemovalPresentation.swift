import ImageLensCore

/// View-only wording for the different ownership boundaries hidden behind the
/// shared canvas removal command. The underlying policy remains the single
/// source of truth for what is actually removed.
@MainActor
struct CanvasRemovalPresentation {
    let title: String
    let systemImage: String
    let help: String

    init(session: WorkspaceSession, contextualNodeID: CanvasNodeID? = nil) {
        let nodeIDs: Set<CanvasNodeID>
        if let contextualNodeID {
            nodeIDs = session.isNodeSelected(contextualNodeID)
                ? session.selectedNodeIDs
                : [contextualNodeID]
        } else {
            nodeIDs = session.selectedNodeIDs
        }

        let nodes = session.workspace.canvasNodes.filter { nodeIDs.contains($0.id) }
        let semantics = Set(
            nodes.map {
                Self.semantic(
                    for: $0,
                    removingNodeIDs: nodeIDs,
                    session: session
                )
            }
        )
        let count = nodes.count

        if semantics.count > 1 {
            title = "删除选中内容…"
            systemImage = "trash"
            help = "删除所选节点或画布实例；生成历史、结果图片和素材文件仍会保留"
            return
        }

        switch semantics.first {
        case .generator:
            title = count > 1 ? "删除 \(count) 个生图节点…" : "删除生图节点…"
            systemImage = "trash"
            help = count > 1
                ? "删除所选生图节点配置；生成历史和结果图片仍会保留"
                : "删除这个生图节点配置；生成历史和结果图片仍会保留"

        case .handwrittenPrompt:
            title = count > 1 ? "删除 \(count) 个提示词…" : "删除提示词…"
            systemImage = "trash"
            help = count > 1
                ? "删除所选手写提示词及其连接；来源图片的结构化提示词不受影响"
                : "删除这个手写提示词及其连接；来源图片的结构化提示词不受影响"

        case .canvasOccurrence, nil:
            title = count > 1 ? "从画布移除 \(count) 个实例" : "从画布移除"
            systemImage = "rectangle.badge.minus"
            help = "仅从画布移除；素材文件、来源分析和生成历史仍会保留"
        }
    }

    private enum Semantic: Hashable {
        case generator
        case handwrittenPrompt
        case canvasOccurrence
    }

    private static func semantic(
        for node: CanvasNode,
        removingNodeIDs: Set<CanvasNodeID>,
        session: WorkspaceSession
    ) -> Semantic {
        if let generatorID = node.generatorID,
           session.generator(for: generatorID) != nil {
            let hasRemainingOccurrence = session.workspace.canvasNodes.contains {
                $0.generatorID == generatorID && !removingNodeIDs.contains($0.id)
            }
            return hasRemainingOccurrence ? .canvasOccurrence : .generator
        }

        guard let moduleID = node.promptModuleID,
              let module = session.promptModule(for: moduleID),
              module.sourceAssetID == nil else {
            return .canvasOccurrence
        }

        let hasRemainingOccurrence = session.workspace.canvasNodes.contains {
            $0.promptModuleID == moduleID && !removingNodeIDs.contains($0.id)
        }
        return hasRemainingOccurrence ? .canvasOccurrence : .handwrittenPrompt
    }
}
