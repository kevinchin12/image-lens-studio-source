import ImageLensCore

/// A transient pointer translation measured in local view points.
public struct ViewDragTranslation: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = ViewDragTranslation(x: 0, y: 0)
}

/// Identifies who owns an active drag. A node-owned drag must never be fed into
/// the viewport pan gesture.
public enum CanvasDragTarget: Hashable, Sendable {
    case canvas
    case node(CanvasNodeID)

    public var permitsCanvasPan: Bool {
        switch self {
        case .canvas: true
        case .node: false
        }
    }
}

/// Reversible, pure-value command produced when a node drag ends.
///
/// The command stores world frames, so it remains deterministic if the viewport
/// changes before persistence or undo is applied.
public struct CanvasNodeMoveCommand: Hashable, Sendable {
    public let nodeID: CanvasNodeID
    public let fromFrame: WorldRect
    public let toFrame: WorldRect

    public init(nodeID: CanvasNodeID, fromFrame: WorldRect, toFrame: WorldRect) {
        self.nodeID = nodeID
        self.fromFrame = fromFrame.standardized
        self.toFrame = toFrame.standardized
    }

    /// Builds the final world-space move from the drag's total view translation.
    /// Viewport translation is intentionally irrelevant; only zoom scales a delta.
    public init(
        node: CanvasNode,
        viewTranslation: ViewDragTranslation,
        viewport: ViewportTransform
    ) {
        let worldX = viewTranslation.x / viewport.scale
        let worldY = viewTranslation.y / viewport.scale
        let destination = WorldRect(
            x: node.frame.minX + worldX,
            y: node.frame.minY + worldY,
            width: node.frame.width,
            height: node.frame.height
        )
        self.init(nodeID: node.id, fromFrame: node.frame, toFrame: destination)
    }

    public var destinationOrigin: WorldPoint { toFrame.origin }

    public var isNoOp: Bool { fromFrame == toFrame }

    public var inverse: CanvasNodeMoveCommand {
        CanvasNodeMoveCommand(nodeID: nodeID, fromFrame: toFrame, toFrame: fromFrame)
    }

    /// Returns an updated node only when the command targets that node. All
    /// non-position fields, including selection identity and z-order, are retained.
    public func applying(to node: CanvasNode) -> CanvasNode? {
        guard node.id == nodeID else { return nil }
        var updated = node
        updated.frame = toFrame
        return updated
    }

    /// Applies the command to a canonical node collection. The boolean reports
    /// whether the target existed; no duplicate placement state is created.
    @discardableResult
    public func apply(to nodes: inout [CanvasNode]) -> Bool {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else {
            return false
        }
        nodes[index].frame = toFrame
        return true
    }
}
