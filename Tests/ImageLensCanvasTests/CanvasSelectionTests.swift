import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class CanvasSelectionTests: XCTestCase {
    private let firstID = CanvasNodeID(
        UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    )
    private let secondID = CanvasNodeID(
        UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    )
    private let thirdID = CanvasNodeID(
        UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    )

    func testReplacementClickSelectsOnlyHitAndEmptyClickClears() {
        let existing = CanvasNodeSelection(nodeIDs: [firstID, secondID], primaryNodeID: secondID)

        let replaced = existing.applyingClick(thirdID)

        XCTAssertEqual(replaced.nodeIDs, [thirdID])
        XCTAssertEqual(replaced.primaryNodeID, thirdID)
        XCTAssertEqual(replaced.applyingClick(nil), .empty)
    }

    func testShiftStyleToggleClickAddsAndRemovesMembership() {
        let initial = CanvasNodeSelection(nodeIDs: [firstID], primaryNodeID: firstID)

        let added = initial.applyingClick(secondID, mutation: .toggle)
        let removed = added.applyingClick(firstID, mutation: .toggle)

        XCTAssertEqual(added.nodeIDs, [firstID, secondID])
        XCTAssertEqual(added.primaryNodeID, secondID)
        XCTAssertEqual(removed.nodeIDs, [secondID])
        XCTAssertEqual(removed.primaryNodeID, secondID)
    }

    func testIntersectingMarqueeReplacesSelectionAndChoosesTopmostHitAsPrimary() {
        let placements = [
            placement(firstID, frame: WorldRect(x: 10, y: 10, width: 30, height: 30), zIndex: 1),
            placement(secondID, frame: WorldRect(x: 90, y: 90, width: 30, height: 30), zIndex: 8),
            placement(thirdID, frame: WorldRect(x: 140, y: 140, width: 30, height: 30), zIndex: 9)
        ]

        let selected = CanvasNodeSelection(nodeIDs: [thirdID]).applyingMarquee(
            to: placements,
            in: WorldRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(selected.nodeIDs, [firstID, secondID])
        XCTAssertEqual(selected.primaryNodeID, secondID)
    }

    func testShiftMarqueeCanAddOrToggleRelativeToGestureStartSelection() {
        let placements = [
            placement(firstID, frame: WorldRect(x: 0, y: 0, width: 20, height: 20)),
            placement(secondID, frame: WorldRect(x: 30, y: 0, width: 20, height: 20)),
            placement(thirdID, frame: WorldRect(x: 80, y: 0, width: 20, height: 20))
        ]
        let baseline = CanvasNodeSelection(nodeIDs: [firstID, thirdID], primaryNodeID: thirdID)
        let marquee = WorldRect(x: 0, y: 0, width: 55, height: 25)

        let added = baseline.applyingMarquee(
            to: placements,
            in: marquee,
            mutation: .add
        )
        let toggled = baseline.applyingMarquee(
            to: placements,
            in: marquee,
            mutation: .toggle
        )

        XCTAssertEqual(added.nodeIDs, [firstID, secondID, thirdID])
        XCTAssertEqual(added.primaryNodeID, secondID)
        XCTAssertEqual(toggled.nodeIDs, [secondID, thirdID])
        XCTAssertEqual(toggled.primaryNodeID, secondID)
    }

    func testPrimaryIsRepairedWhenInitializerReceivesUnselectedID() throws {
        let selection = CanvasNodeSelection(
            nodeIDs: [secondID, firstID],
            primaryNodeID: thirdID
        )

        XCTAssertEqual(selection.primaryNodeID, firstID)
        let encoded = try JSONEncoder().encode(selection)
        XCTAssertEqual(try JSONDecoder().decode(CanvasNodeSelection.self, from: encoded), selection)
    }

    private func placement(
        _ id: CanvasNodeID,
        frame: WorldRect,
        zIndex: Int = 0
    ) -> CanvasNodePlacement {
        CanvasNodePlacement(id: id.rawValue, frame: frame, zIndex: zIndex)
    }
}
