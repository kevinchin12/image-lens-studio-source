import ImageLensCanvas
import ImageLensCore
import XCTest

final class CanvasNodeResizeCommandTests: XCTestCase {
    func testFreeResizeConvertsViewTranslationThroughZoom() {
        let initial = WorldRect(x: 10, y: 20, width: 300, height: 200)
        let policy = CanvasNodeResizePolicy(
            minimumSize: WorldSize(width: 100, height: 100)
        )

        XCTAssertEqual(
            policy.frame(
                from: initial,
                viewTranslation: ViewDragTranslation(x: 60, y: 30),
                viewportScale: 2
            ),
            WorldRect(x: 10, y: 20, width: 330, height: 215)
        )
    }

    func testResizeClampsWithoutMovingTopLeftCorner() {
        let initial = WorldRect(x: 10, y: 20, width: 300, height: 200)
        let policy = CanvasNodeResizePolicy(
            minimumSize: WorldSize(width: 220, height: 120)
        )

        XCTAssertEqual(
            policy.frame(
                from: initial,
                viewTranslation: ViewDragTranslation(x: -1_000, y: -1_000),
                viewportScale: 1
            ),
            WorldRect(x: 10, y: 20, width: 220, height: 120)
        )
    }

    func testImageResizePreservesAspectRatio() {
        let initial = WorldRect(x: 10, y: 20, width: 320, height: 180)
        let policy = CanvasNodeResizePolicy.standard(for: .image)
        let frame = policy.frame(
            from: initial,
            viewTranslation: ViewDragTranslation(x: 160, y: 0),
            viewportScale: 1
        )

        XCTAssertEqual(frame.origin, initial.origin)
        XCTAssertEqual(frame.width, 480, accuracy: 0.001)
        XCTAssertEqual(frame.height, 270, accuracy: 0.001)
    }

    func testTopLeftResizeKeepsOppositeCornerFixed() {
        let initial = WorldRect(x: 100, y: 200, width: 300, height: 200)
        let policy = CanvasNodeResizePolicy(
            minimumSize: WorldSize(width: 220, height: 120)
        )
        let frame = policy.frame(
            from: initial,
            viewTranslation: ViewDragTranslation(x: 40, y: 50),
            viewportScale: 1,
            edge: .topLeft
        )

        XCTAssertEqual(frame, WorldRect(x: 140, y: 250, width: 260, height: 150))
        XCTAssertEqual(frame.maxX, initial.maxX)
        XCTAssertEqual(frame.maxY, initial.maxY)
    }

    func testAspectResizeFromRightEdgeKeepsVerticalCenter() {
        let initial = WorldRect(x: 10, y: 20, width: 320, height: 180)
        let policy = CanvasNodeResizePolicy.standard(for: .image)
        let frame = policy.frame(
            from: initial,
            viewTranslation: ViewDragTranslation(x: 160, y: 100),
            viewportScale: 1,
            edge: .right
        )

        XCTAssertEqual(frame.minX, initial.minX, accuracy: 0.001)
        XCTAssertEqual(frame.width, 480, accuracy: 0.001)
        XCTAssertEqual(frame.height, 270, accuracy: 0.001)
        XCTAssertEqual(frame.minY, -25, accuracy: 0.001)
    }

    func testLeftEdgeClampKeepsRightEdgeFixed() {
        let initial = WorldRect(x: 100, y: 200, width: 300, height: 200)
        let policy = CanvasNodeResizePolicy(
            minimumSize: WorldSize(width: 220, height: 120)
        )
        let frame = policy.frame(
            from: initial,
            viewTranslation: ViewDragTranslation(x: 1_000, y: 0),
            viewportScale: 1,
            edge: .left
        )

        XCTAssertEqual(frame, WorldRect(x: 180, y: 200, width: 220, height: 200))
    }

    func testCommandAppliesOnlyToTargetAndCanBeInverted() {
        let node = CanvasNode(
            imageAssetID: AssetID(),
            frame: WorldRect(x: 1, y: 2, width: 320, height: 240)
        )
        let other = CanvasNode(
            imageAssetID: AssetID(),
            frame: WorldRect(x: 9, y: 8, width: 320, height: 240)
        )
        let destination = WorldRect(x: 1, y: 2, width: 480, height: 360)
        let command = CanvasNodeResizeCommand(
            nodeID: node.id,
            fromFrame: node.frame,
            toFrame: destination
        )
        var nodes = [node, other]

        XCTAssertTrue(command.apply(to: &nodes))
        XCTAssertEqual(nodes[0].frame, destination)
        XCTAssertEqual(nodes[1], other)
        XCTAssertTrue(command.inverse.apply(to: &nodes))
        XCTAssertEqual(nodes[0], node)
    }
}
