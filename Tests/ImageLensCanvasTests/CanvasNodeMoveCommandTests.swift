import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class CanvasNodeMoveCommandTests: XCTestCase {
    func testViewTranslationConvertsToWorldTranslationAtZoom() {
        let node = makeNode(frame: WorldRect(x: 100, y: -40, width: 320, height: 240))
        let viewport = ViewportTransform(
            scale: 2.5,
            translation: ViewPoint(x: 700, y: -300)
        )

        let command = CanvasNodeMoveCommand(
            node: node,
            viewTranslation: ViewDragTranslation(x: 125, y: -50),
            viewport: viewport
        )

        XCTAssertEqual(command.toFrame, WorldRect(x: 150, y: -60, width: 320, height: 240))
        XCTAssertEqual(command.destinationOrigin, WorldPoint(x: 150, y: -60))
    }

    func testApplyingMoveUpdatesOnlyFrameAndKeepsStableNodeIdentity() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let node = makeNode(
            frame: WorldRect(x: 10, y: 20, width: 320, height: 240),
            zIndex: 8,
            createdAt: timestamp
        )
        let command = CanvasNodeMoveCommand(
            node: node,
            viewTranslation: ViewDragTranslation(x: 36, y: 48),
            viewport: .identity
        )

        let moved = try XCTUnwrap(command.applying(to: node))

        XCTAssertEqual(moved.id, node.id)
        XCTAssertEqual(moved.kind, node.kind)
        XCTAssertEqual(moved.entityID, node.entityID)
        XCTAssertEqual(moved.zIndex, 8)
        XCTAssertEqual(moved.createdAt, timestamp)
        XCTAssertEqual(moved.frame, WorldRect(x: 46, y: 68, width: 320, height: 240))
    }

    func testCollectionApplyOnlyTouchesTargetAndInverseRestoresFrame() {
        let first = makeNode(frame: WorldRect(x: 0, y: 0, width: 320, height: 240))
        let second = makeNode(frame: WorldRect(x: 500, y: 400, width: 320, height: 240))
        var nodes = [first, second]
        let command = CanvasNodeMoveCommand(
            node: first,
            viewTranslation: ViewDragTranslation(x: -80, y: 120),
            viewport: ViewportTransform(scale: 2)
        )

        XCTAssertTrue(command.apply(to: &nodes))
        XCTAssertEqual(nodes[0].frame, WorldRect(x: -40, y: 60, width: 320, height: 240))
        XCTAssertEqual(nodes[1], second)

        XCTAssertTrue(command.inverse.apply(to: &nodes))
        XCTAssertEqual(nodes, [first, second])
    }

    func testMismatchedNodeAndMissingCollectionTargetAreNoOps() {
        let source = makeNode(frame: WorldRect(x: 0, y: 0, width: 320, height: 240))
        let other = makeNode(frame: WorldRect(x: 400, y: 0, width: 320, height: 240))
        let command = CanvasNodeMoveCommand(
            node: source,
            viewTranslation: ViewDragTranslation(x: 10, y: 20),
            viewport: .identity
        )
        var nodes = [other]

        XCTAssertNil(command.applying(to: other))
        XCTAssertFalse(command.apply(to: &nodes))
        XCTAssertEqual(nodes, [other])
    }

    func testDragOwnershipPreventsNodeDragFromBecomingCanvasPan() {
        let node = makeNode(frame: WorldRect(x: 0, y: 0, width: 320, height: 240))

        XCTAssertTrue(CanvasDragTarget.canvas.permitsCanvasPan)
        XCTAssertFalse(CanvasDragTarget.node(node.id).permitsCanvasPan)
    }

    private func makeNode(
        frame: WorldRect,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) -> CanvasNode {
        CanvasNode(
            imageAssetID: AssetID(),
            frame: frame,
            zIndex: zIndex,
            createdAt: createdAt
        )
    }
}
