import Foundation
import ImageLensCore

/// The minimum placement information needed by the canvas rendering layer.
public struct CanvasNodePlacement: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var frame: WorldRect
    public var zIndex: Int

    public init(id: UUID = UUID(), frame: WorldRect, zIndex: Int = 0) {
        self.id = id
        self.frame = frame.standardized
        self.zIndex = zIndex
    }

    /// Creates the lightweight render/index projection of a canonical node.
    public init(node: CanvasNode) {
        self.init(id: node.id.rawValue, frame: node.frame, zIndex: node.zIndex)
    }
}

public enum CanvasSelectionMode: Codable, Hashable, Sendable {
    /// Select every node with area overlapping the marquee.
    case intersecting
    /// Select only nodes whose complete frame is inside the marquee.
    case contained
}

/// Linear culling helpers suitable for ordinary workspaces and as a reference
/// implementation for indexed culling.
public enum CanvasCulling {
    public static func visiblePlacements(
        from placements: some Sequence<CanvasNodePlacement>,
        transform: ViewportTransform,
        viewportSize: ViewSize,
        overscanInViewPoints: Double = 0
    ) -> [CanvasNodePlacement] {
        guard !viewportSize.isEmpty else { return [] }
        let worldMargin = Swift.max(overscanInViewPoints, 0) / transform.scale
        let visibleRect = transform.visibleWorldRect(viewportSize: viewportSize).expanded(by: worldMargin)
        return sorted(placements.lazy.filter { $0.frame.intersects(visibleRect) })
    }

    public static func selectedPlacements(
        from placements: some Sequence<CanvasNodePlacement>,
        in selectionRect: WorldRect,
        mode: CanvasSelectionMode = .intersecting
    ) -> [CanvasNodePlacement] {
        let rect = selectionRect.standardized
        guard !rect.isEmpty else { return [] }

        return sorted(placements.lazy.filter { placement in
            switch mode {
            case .intersecting:
                placement.frame.intersects(rect)
            case .contained:
                rect.contains(placement.frame)
            }
        })
    }

    fileprivate static func sorted(
        _ placements: some Sequence<CanvasNodePlacement>
    ) -> [CanvasNodePlacement] {
        placements.sorted {
            if $0.zIndex != $1.zIndex { return $0.zIndex < $1.zIndex }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

/// A mutable uniform-grid index for workspaces large enough that linear culling
/// becomes wasteful. Query results are exact: grid cells provide candidates,
/// followed by a rectangle intersection check.
public struct UniformGridSpatialIndex: Sendable {
    public let cellSize: Double

    private var placementsByID: [UUID: CanvasNodePlacement]
    private var buckets: [Cell: Set<UUID>]

    public init(cellSize: Double = 512) {
        precondition(cellSize.isFinite && cellSize > 0, "Grid cell size must be finite and positive")
        self.cellSize = cellSize
        self.placementsByID = [:]
        self.buckets = [:]
    }

    public init(
        placements: some Sequence<CanvasNodePlacement>,
        cellSize: Double = 512
    ) {
        self.init(cellSize: cellSize)
        for placement in placements {
            insert(placement)
        }
    }

    public var count: Int { placementsByID.count }

    public var allPlacements: [CanvasNodePlacement] {
        CanvasCulling.sorted(placementsByID.values)
    }

    /// Inserts a placement, replacing an existing placement with the same ID.
    public mutating func insert(_ placement: CanvasNodePlacement) {
        remove(id: placement.id)
        placementsByID[placement.id] = placement
        for cell in cells(overlapping: placement.frame) {
            buckets[cell, default: []].insert(placement.id)
        }
    }

    public mutating func remove(id: UUID) {
        guard let placement = placementsByID.removeValue(forKey: id) else { return }
        for cell in cells(overlapping: placement.frame) {
            buckets[cell]?.remove(id)
            if buckets[cell]?.isEmpty == true {
                buckets.removeValue(forKey: cell)
            }
        }
    }

    public func placement(id: UUID) -> CanvasNodePlacement? {
        placementsByID[id]
    }

    public func placements(intersecting region: WorldRect) -> [CanvasNodePlacement] {
        let rect = region.standardized
        guard !rect.isEmpty else { return [] }

        var candidateIDs: Set<UUID> = []
        for cell in cells(overlapping: rect) {
            if let ids = buckets[cell] {
                candidateIDs.formUnion(ids)
            }
        }

        return CanvasCulling.sorted(candidateIDs.compactMap { id in
            guard let placement = placementsByID[id], placement.frame.intersects(rect) else {
                return nil
            }
            return placement
        })
    }

    public func visiblePlacements(
        transform: ViewportTransform,
        viewportSize: ViewSize,
        overscanInViewPoints: Double = 0
    ) -> [CanvasNodePlacement] {
        guard !viewportSize.isEmpty else { return [] }
        let worldMargin = Swift.max(overscanInViewPoints, 0) / transform.scale
        let region = transform.visibleWorldRect(viewportSize: viewportSize).expanded(by: worldMargin)
        return placements(intersecting: region)
    }

    private func cells(overlapping rect: WorldRect) -> [Cell] {
        let rect = rect.standardized
        let firstColumn = Int(floor(rect.minX / cellSize))
        let firstRow = Int(floor(rect.minY / cellSize))
        // Rectangles use half-open area semantics for intersection. `nextDown`
        // avoids unnecessarily indexing the neighbor when maxX/maxY is exactly
        // on a cell boundary.
        let lastX = rect.width > 0 ? rect.maxX.nextDown : rect.maxX
        let lastY = rect.height > 0 ? rect.maxY.nextDown : rect.maxY
        let lastColumn = Int(floor(lastX / cellSize))
        let lastRow = Int(floor(lastY / cellSize))

        var result: [Cell] = []
        result.reserveCapacity((lastColumn - firstColumn + 1) * (lastRow - firstRow + 1))
        for column in firstColumn ... lastColumn {
            for row in firstRow ... lastRow {
                result.append(Cell(column: column, row: row))
            }
        }
        return result
    }

    private struct Cell: Hashable, Sendable {
        let column: Int
        let row: Int
    }
}
