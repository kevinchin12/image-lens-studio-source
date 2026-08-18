import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class CanvasNodeGroupMoveCommandTests: XCTestCase {
    func testGroupDragCalculatesWorldOriginsForOnlySelectedNodes() throws {
        let first = node(
            id: "20000000-0000-0000-0000-000000000001",
            frame: WorldRect(x: 10, y: 20, width: 100, height: 80)
        )
        let second = node(
            id: "20000000-0000-0000-0000-000000000002",
            frame: WorldRect(x: -40, y: 200, width: 120, height: 90)
        )
        let unselected = node(
            id: "20000000-0000-0000-0000-000000000003",
            frame: WorldRect(x: 500, y: 500, width: 80, height: 80)
        )
        let selection = CanvasNodeSelection(nodeIDs: [first.id, second.id])

        let command = CanvasNodeGroupMoveCommand(
            nodes: [unselected, second, first],
            selection: selection,
            viewTranslation: ViewDragTranslation(x: 90, y: -45),
            viewport: ViewportTransform(
                scale: 1.5,
                translation: ViewPoint(x: 600, y: -300)
            )
        )

        XCTAssertEqual(command.moves.map(\.nodeID), [first.id, second.id])
        XCTAssertEqual(
            try XCTUnwrap(command.destinationOrigin(for: first.id)),
            WorldPoint(x: 70, y: -10)
        )
        XCTAssertEqual(
            try XCTUnwrap(command.destinationOrigins[second.id]),
            WorldPoint(x: 20, y: 170)
        )
        XCTAssertNil(command.destinationOrigin(for: unselected.id))
    }

    func testApplyMovesWholeGroupAndInverseRestoresOriginalFrames() {
        let first = node(
            id: "20000000-0000-0000-0000-000000000011",
            frame: WorldRect(x: 0, y: 0, width: 100, height: 80)
        )
        let second = node(
            id: "20000000-0000-0000-0000-000000000012",
            frame: WorldRect(x: 200, y: 100, width: 120, height: 90)
        )
        let untouched = node(
            id: "20000000-0000-0000-0000-000000000013",
            frame: WorldRect(x: 500, y: 500, width: 80, height: 80)
        )
        var nodes = [first, second, untouched]
        let command = CanvasNodeGroupMoveCommand(
            nodes: nodes,
            selectedNodeIDs: [first.id, second.id],
            viewTranslation: ViewDragTranslation(x: 40, y: 60),
            viewport: ViewportTransform(scale: 2)
        )

        XCTAssertEqual(command.apply(to: &nodes), 2)
        XCTAssertEqual(nodes[0].frame.origin, WorldPoint(x: 20, y: 30))
        XCTAssertEqual(nodes[1].frame.origin, WorldPoint(x: 220, y: 130))
        XCTAssertEqual(nodes[2], untouched)

        XCTAssertEqual(command.inverse.apply(to: &nodes), 2)
        XCTAssertEqual(nodes, [first, second, untouched])
    }

    func testEmptyAndZeroTranslationCommandsHaveExplicitSemantics() {
        let first = node(
            id: "20000000-0000-0000-0000-000000000021",
            frame: WorldRect(x: 0, y: 0, width: 100, height: 80)
        )

        let empty = CanvasNodeGroupMoveCommand(
            nodes: [first],
            selectedNodeIDs: [],
            viewTranslation: .zero,
            viewport: .identity
        )
        let stationary = CanvasNodeGroupMoveCommand(
            nodes: [first],
            selectedNodeIDs: [first.id],
            viewTranslation: .zero,
            viewport: .identity
        )

        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.isNoOp)
        XCTAssertFalse(stationary.isEmpty)
        XCTAssertTrue(stationary.isNoOp)
        XCTAssertEqual(stationary.destinationOrigins[first.id], first.frame.origin)
    }

    private func node(id: String, frame: WorldRect) -> CanvasNode {
        CanvasNode(
            id: CanvasNodeID(UUID(uuidString: id)!),
            imageAssetID: AssetID(),
            frame: frame
        )
    }
}
