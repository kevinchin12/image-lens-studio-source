import XCTest
@testable import ImageLensCanvas

final class CanvasScrollZoomPolicyTests: XCTestCase {
    func testPositiveAndNegativeWheelDeltasAreReciprocal() throws {
        let zoomIn = try XCTUnwrap(
            CanvasScrollZoomPolicy.factor(deltaY: 1, isPrecise: false)
        )
        let zoomOut = try XCTUnwrap(
            CanvasScrollZoomPolicy.factor(deltaY: -1, isPrecise: false)
        )

        XCTAssertGreaterThan(zoomIn, 1)
        XCTAssertLessThan(zoomOut, 1)
        XCTAssertEqual(zoomIn * zoomOut, 1, accuracy: 0.000_001)
    }

    func testPreciseScrollingUsesGentlerContinuousSteps() throws {
        let precise = try XCTUnwrap(
            CanvasScrollZoomPolicy.factor(deltaY: 1, isPrecise: true)
        )
        let wheel = try XCTUnwrap(
            CanvasScrollZoomPolicy.factor(deltaY: 1, isPrecise: false)
        )

        XCTAssertGreaterThan(precise, 1)
        XCTAssertLessThan(precise, wheel)
    }

    func testZeroAndNonFiniteDeltasDoNotZoom() {
        XCTAssertNil(CanvasScrollZoomPolicy.factor(deltaY: 0, isPrecise: false))
        XCTAssertNil(CanvasScrollZoomPolicy.factor(deltaY: .infinity, isPrecise: false))
        XCTAssertNil(CanvasScrollZoomPolicy.factor(deltaY: .nan, isPrecise: true))
    }

    func testExtremeDeltasAreClamped() throws {
        let positive = try XCTUnwrap(
            CanvasScrollZoomPolicy.factor(deltaY: 10_000, isPrecise: false)
        )
        let negative = try XCTUnwrap(
            CanvasScrollZoomPolicy.factor(deltaY: -10_000, isPrecise: false)
        )

        XCTAssertEqual(positive, exp(1.2), accuracy: 0.000_001)
        XCTAssertEqual(negative, exp(-1.2), accuracy: 0.000_001)
    }
}
