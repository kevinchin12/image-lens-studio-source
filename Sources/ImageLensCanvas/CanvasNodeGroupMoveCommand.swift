import ImageLensCore

/// Reversible world-space movement for every selected node in one drag.
///
/// Commands are sorted by stable node identity, so equal group moves compare
/// and hash identically regardless of the source collection's render order.
public struct CanvasNodeGroupMoveCommand: Hashable, Sendable {
    public let moves: [CanvasNodeMoveCommand]

    public init(
        nodes: some Sequence<CanvasNode>,
        selection: CanvasNodeSelection,
        viewTranslation: ViewDragTranslation,
        viewport: ViewportTransform
    ) {
        self.init(
            nodes: nodes,
            selectedNodeIDs: selection.nodeIDs,
            viewTranslation: viewTranslation,
            viewport: viewport
        )
    }

    public init(
        nodes: some Sequence<CanvasNode>,
        selectedNodeIDs: Set<CanvasNodeID>,
        viewTranslation: ViewDragTranslation,
        viewport: ViewportTransform
    ) {
        moves = nodes.lazy
            .filter { selectedNodeIDs.contains($0.id) }
            .map {
                CanvasNodeMoveCommand(
                    node: $0,
                    viewTranslation: viewTranslation,
                    viewport: viewport
                )
            }
            .sorted {
                $0.nodeID.rawValue.uuidString < $1.nodeID.rawValue.uuidString
            }
    }

    public var isEmpty: Bool { moves.isEmpty }

    public var isNoOp: Bool { moves.allSatisfy(\.isNoOp) }

    public var destinationOrigins: [CanvasNodeID: WorldPoint] {
        Dictionary(uniqueKeysWithValues: moves.map { ($0.nodeID, $0.destinationOrigin) })
    }

    public func destinationOrigin(for nodeID: CanvasNodeID) -> WorldPoint? {
        moves.first(where: { $0.nodeID == nodeID })?.destinationOrigin
    }

    public var inverse: CanvasNodeGroupMoveCommand {
        CanvasNodeGroupMoveCommand(moves: moves.map(\.inverse))
    }

    /// Applies all commands whose nodes still exist and returns their count.
    /// Missing nodes do not prevent the remaining group from moving.
    @discardableResult
    public func apply(to nodes: inout [CanvasNode]) -> Int {
        let indicesByID = Dictionary(
            uniqueKeysWithValues: nodes.indices.map { (nodes[$0].id, $0) }
        )
        var appliedCount = 0
        for move in moves {
            guard let index = indicesByID[move.nodeID] else { continue }
            nodes[index].frame = move.toFrame
            appliedCount += 1
        }
        return appliedCount
    }

    private init(moves: [CanvasNodeMoveCommand]) {
        self.moves = moves
    }
}
