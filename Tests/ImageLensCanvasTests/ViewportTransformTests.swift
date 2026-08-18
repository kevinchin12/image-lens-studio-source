import XCTest
@testable import ImageLensCanvas

final class ViewportTransformTests: XCTestCase {
    func testWorldViewRoundTripAtScaleAndTranslation() {
        let transform = ViewportTransform(
            scale: 2.75,
            translation: ViewPoint(x: 190, y: -84)
        )
        let worldPoint = WorldPoint(x: -321.25, y: 42.5)

        let viewPoint = transform.viewPoint(for: worldPoint)
        let roundTrippedPoint = transform.worldPoint(for: viewPoint)

        XCTAssertEqual(roundTrippedPoint.x, worldPoint.x, accuracy: 1e-10)
        XCTAssertEqual(roundTrippedPoint.y, worldPoint.y, accuracy: 1e-10)
    }

    func testWorldViewRectRoundTripStandardizesDragRect() {
        let transform = ViewportTransform(
            scale: 0.75,
            translation: ViewPoint(x: -20, y: 50)
        )
        let dragRect = WorldRect(x: 80, y: 30, width: -120, height: -90)

        let viewRect = transform.viewRect(for: dragRect)
        let worldRect = transform.worldRect(for: viewRect)

        XCTAssertEqual(worldRect.origin.x, -40, accuracy: 1e-10)
        XCTAssertEqual(worldRect.origin.y, -60, accuracy: 1e-10)
        XCTAssertEqual(worldRect.size.width, 120, accuracy: 1e-10)
        XCTAssertEqual(worldRect.size.height, 90, accuracy: 1e-10)
    }

    func testAnchorZoomKeepsSameWorldPointUnderPointer() {
        let transform = ViewportTransform(
            scale: 1.25,
            translation: ViewPoint(x: 70, y: -45)
        )
        let anchor = ViewPoint(x: 412, y: 288)
        let worldBeforeZoom = transform.worldPoint(for: anchor)

        let zoomed = transform.zoomed(to: 4.5, around: anchor)
        let worldAfterZoom = zoomed.worldPoint(for: anchor)

        XCTAssertEqual(worldAfterZoom.x, worldBeforeZoom.x, accuracy: 1e-10)
        XCTAssertEqual(worldAfterZoom.y, worldBeforeZoom.y, accuracy: 1e-10)
        XCTAssertEqual(zoomed.viewPoint(for: worldBeforeZoom).x, anchor.x, accuracy: 1e-10)
        XCTAssertEqual(zoomed.viewPoint(for: worldBeforeZoom).y, anchor.y, accuracy: 1e-10)
    }

    func testFactorZoomClampsAndStillPreservesAnchor() {
        let transform = ViewportTransform(scale: 2, translation: .zero)
        let anchor = ViewPoint(x: 100, y: 200)
        let worldBeforeZoom = transform.worldPoint(for: anchor)

        let zoomed = transform.zoomed(by: 100, around: anchor, limitedTo: 0.5 ... 5)

        XCTAssertEqual(zoomed.scale, 5)
        XCTAssertEqual(zoomed.worldPoint(for: anchor).x, worldBeforeZoom.x, accuracy: 1e-10)
        XCTAssertEqual(zoomed.worldPoint(for: anchor).y, worldBeforeZoom.y, accuracy: 1e-10)
    }

    func testContinuousIncrementalZoomPreservesFrozenGestureAnchor() {
        let anchor = ViewPoint(x: 318.5, y: 227.25)
        var transform = ViewportTransform(
            scale: 0.85,
            translation: ViewPoint(x: -120, y: 76)
        )
        let worldPointAtGestureStart = transform.worldPoint(for: anchor)

        for factor in [1.012, 1.027, 0.994, 1.041, 0.981, 1.006] {
            transform = transform.zoomed(
                by: factor,
                around: anchor,
                limitedTo: 0.2 ... 4
            )

            let worldPointUnderAnchor = transform.worldPoint(for: anchor)
            XCTAssertEqual(worldPointUnderAnchor.x, worldPointAtGestureStart.x, accuracy: 1e-10)
            XCTAssertEqual(worldPointUnderAnchor.y, worldPointAtGestureStart.y, accuracy: 1e-10)
        }
    }

    func testContinuousZoomHonorsCanvasScaleBounds() {
        let anchor = ViewPoint(x: 50, y: 80)
        let transform = ViewportTransform(scale: 1, translation: .zero)

        let minimum = transform.zoomed(by: 0.001, around: anchor, limitedTo: 0.2 ... 4)
        let maximum = minimum.zoomed(by: 10_000, around: anchor, limitedTo: 0.2 ... 4)

        XCTAssertEqual(minimum.scale, 0.2)
        XCTAssertEqual(maximum.scale, 4)
    }

    func testPanningUsesViewPointDelta() {
        let transform = ViewportTransform(scale: 3, translation: ViewPoint(x: 5, y: 8))
        let panned = transform.pannedBy(x: 20, y: -12)

        XCTAssertEqual(panned.translation, ViewPoint(x: 25, y: -4))
        XCTAssertEqual(panned.scale, 3)
    }
}
