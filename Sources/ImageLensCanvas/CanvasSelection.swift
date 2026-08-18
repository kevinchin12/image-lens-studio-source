import ImageLensCore

/// How a click or marquee result combines with the current selection.
public enum CanvasSelectionMutation: String, Codable, CaseIterable, Hashable, Sendable {
    /// The new hit set becomes the complete selection.
    case replace
    /// Every hit is added while preserving the existing selection.
    case add
    /// Every hit switches membership relative to the selection at gesture start.
    case toggle
}

/// Pure-value transient selection state for the canvas.
///
/// `primaryNodeID` is suitable for driving a single-item inspector while
/// `nodeIDs` remains the source of truth for multi-node affordances.
public struct CanvasNodeSelection: Codable, Hashable, Sendable {
    public private(set) var nodeIDs: Set<CanvasNodeID>
    public private(set) var primaryNodeID: CanvasNodeID?

    public init(
        nodeIDs: Set<CanvasNodeID> = [],
        primaryNodeID: CanvasNodeID? = nil
    ) {
        self.nodeIDs = nodeIDs
        if let primaryNodeID, nodeIDs.contains(primaryNodeID) {
            self.primaryNodeID = primaryNodeID
        } else {
            self.primaryNodeID = Self.deterministicPrimary(in: nodeIDs)
        }
    }

    public static let empty = CanvasNodeSelection()

    public var isEmpty: Bool { nodeIDs.isEmpty }

    public var count: Int { nodeIDs.count }

    public func contains(_ nodeID: CanvasNodeID) -> Bool {
        nodeIDs.contains(nodeID)
    }

    /// Applies one hit-tested node. Passing `nil` clears a replacement click,
    /// while additive and toggle clicks on empty canvas preserve the selection.
    public func applyingClick(
        _ nodeID: CanvasNodeID?,
        mutation: CanvasSelectionMutation = .replace
    ) -> CanvasNodeSelection {
        applying(nodeIDs: nodeID.map { [$0] } ?? [], mutation: mutation)
    }

    /// Selects placements hit by a marquee in world coordinates, then combines
    /// the hit set with this selection using the supplied mutation.
    ///
    /// Call this against the selection captured when the marquee begins. That
    /// makes repeated drag updates deterministic, especially for `.toggle`.
    public func applyingMarquee(
        to placements: some Sequence<CanvasNodePlacement>,
        in selectionRect: WorldRect,
        mode: CanvasSelectionMode = .intersecting,
        mutation: CanvasSelectionMutation = .replace
    ) -> CanvasNodeSelection {
        let hits = CanvasCulling.selectedPlacements(
            from: placements,
            in: selectionRect,
            mode: mode
        )
        return applying(
            nodeIDs: hits.map { CanvasNodeID($0.id) },
            mutation: mutation
        )
    }

    /// Combines an already hit-tested node sequence with this selection.
    /// Candidate ordering is retained to choose a predictable primary node.
    public func applying(
        nodeIDs candidates: some Sequence<CanvasNodeID>,
        mutation: CanvasSelectionMutation
    ) -> CanvasNodeSelection {
        let orderedCandidates = Self.uniqued(candidates)
        let candidateSet = Set(orderedCandidates)
        var result = nodeIDs

        switch mutation {
        case .replace:
            result = candidateSet
        case .add:
            result.formUnion(candidateSet)
        case .toggle:
            result.formSymmetricDifference(candidateSet)
        }

        let primary: CanvasNodeID?
        switch mutation {
        case .replace:
            primary = orderedCandidates.last
        case .add:
            primary = orderedCandidates.last ?? primaryNodeID
        case .toggle:
            primary = orderedCandidates.reversed().first(where: {
                !nodeIDs.contains($0) && result.contains($0)
            }) ?? retainedPrimary(in: result)
        }

        return CanvasNodeSelection(nodeIDs: result, primaryNodeID: primary)
    }

    private func retainedPrimary(in result: Set<CanvasNodeID>) -> CanvasNodeID? {
        if let primaryNodeID, result.contains(primaryNodeID) {
            return primaryNodeID
        }
        return Self.deterministicPrimary(in: result)
    }

    private static func uniqued(
        _ candidates: some Sequence<CanvasNodeID>
    ) -> [CanvasNodeID] {
        var seen: Set<CanvasNodeID> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func deterministicPrimary(
        in nodeIDs: Set<CanvasNodeID>
    ) -> CanvasNodeID? {
        nodeIDs.min { $0.rawValue.uuidString < $1.rawValue.uuidString }
    }
}
