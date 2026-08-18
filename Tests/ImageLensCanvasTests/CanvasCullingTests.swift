import Foundation
import XCTest
@testable import ImageLensCanvas

final class CanvasCullingTests: XCTestCase {
    private let insideID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let partialID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let outsideID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let edgeID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    func testMarqueeSelectionSupportsIntersectingAndContainedModes() {
        let placements = makePlacements()
        // Negative dimensions mirror an up-and-left marquee drag.
        let marquee = WorldRect(x: 100, y: 100, width: -100, height: -100)

        let intersecting = CanvasCulling.selectedPlacements(
            from: placements,
            in: marquee,
            mode: .intersecting
        )
        let contained = CanvasCulling.selectedPlacements(
            from: placements,
            in: marquee,
            mode: .contained
        )

        XCTAssertEqual(intersecting.map(\.id), [insideID, partialID])
        XCTAssertEqual(contained.map(\.id), [insideID])
    }

    func testVisibleCullingConvertsViewportToWorldCoordinates() {
        // Viewport (0, 0, 200, 100) maps to world (50, 25, 100, 50).
        let transform = ViewportTransform(
            scale: 2,
            translation: ViewPoint(x: -100, y: -50)
        )
        let placements = [
            CanvasNodePlacement(id: insideID, frame: WorldRect(x: 60, y: 30, width: 20, height: 20)),
            CanvasNodePlacement(id: partialID, frame: WorldRect(x: 140, y: 65, width: 20, height: 20)),
            CanvasNodePlacement(id: outsideID, frame: WorldRect(x: 151, y: 80, width: 20, height: 20)),
            CanvasNodePlacement(id: edgeID, frame: WorldRect(x: 150, y: 40, width: 20, height: 20))
        ]

        let visible = CanvasCulling.visiblePlacements(
            from: placements,
            transform: transform,
            viewportSize: ViewSize(width: 200, height: 100)
        )

        XCTAssertEqual(visible.map(\.id), [insideID, partialID])
    }

    func testVisibleCullingSupportsViewPointOverscan() {
        let transform = ViewportTransform(scale: 2)
        let placement = CanvasNodePlacement(
            id: outsideID,
            frame: WorldRect(x: 105, y: 10, width: 10, height: 10)
        )

        XCTAssertTrue(
            CanvasCulling.visiblePlacements(
                from: [placement],
                transform: transform,
                viewportSize: ViewSize(width: 200, height: 100)
            ).isEmpty
        )
        XCTAssertEqual(
            CanvasCulling.visiblePlacements(
                from: [placement],
                transform: transform,
                viewportSize: ViewSize(width: 200, height: 100),
                overscanInViewPoints: 20
            ).map(\.id),
            [outsideID]
        )
    }

    func testUniformGridMatchesLinearCullingAndSupportsReplacementAndRemoval() {
        let placements = makePlacements()
        var index = UniformGridSpatialIndex(placements: placements, cellSize: 50)
        let query = WorldRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertEqual(
            index.placements(intersecting: query).map(\.id),
            CanvasCulling.selectedPlacements(from: placements, in: query).map(\.id)
        )

        index.insert(
            CanvasNodePlacement(
                id: partialID,
                frame: WorldRect(x: 500, y: 500, width: 20, height: 20)
            )
        )
        XCTAssertEqual(index.placements(intersecting: query).map(\.id), [insideID])

        index.remove(id: insideID)
        XCTAssertTrue(index.placements(intersecting: query).isEmpty)
        XCTAssertEqual(index.count, placements.count - 1)
    }

    private func makePlacements() -> [CanvasNodePlacement] {
        [
            CanvasNodePlacement(id: insideID, frame: WorldRect(x: 10, y: 10, width: 20, height: 20)),
            CanvasNodePlacement(id: partialID, frame: WorldRect(x: 90, y: 90, width: 20, height: 20)),
            CanvasNodePlacement(id: outsideID, frame: WorldRect(x: 150, y: 150, width: 20, height: 20)),
            // Touches the marquee at x = 100 but has no overlapping area.
            CanvasNodePlacement(id: edgeID, frame: WorldRect(x: 100, y: 20, width: 20, height: 20))
        ]
    }
}
