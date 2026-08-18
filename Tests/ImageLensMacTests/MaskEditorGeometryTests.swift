import AppKit
import XCTest
@testable import ImageLensMac

final class MaskEditorGeometryTests: XCTestCase {
    func testWideImageFitsViewportAndRoundTripsPixelCoordinates() throws {
        let geometry = MaskEditorGeometry(
            imagePixelSize: CGSize(width: 1600, height: 900),
            viewportSize: CGSize(width: 1000, height: 700)
        )

        XCTAssertEqual(geometry.fitScale, 0.595, accuracy: 0.000_001)
        XCTAssertEqual(geometry.imageRect, CGRect(x: 24, y: 82.25, width: 952, height: 535.5))

        let imagePoint = CGPoint(x: 421.5, y: 377.25)
        let viewPoint = geometry.viewPoint(fromImagePoint: imagePoint)
        let roundTripped = try XCTUnwrap(geometry.imagePoint(fromViewPoint: viewPoint))
        XCTAssertEqual(roundTripped.x, imagePoint.x, accuracy: 0.000_001)
        XCTAssertEqual(roundTripped.y, imagePoint.y, accuracy: 0.000_001)
    }

    func testLetterboxRejectsPaintingOutsideDisplayedImage() {
        let geometry = MaskEditorGeometry(
            imagePixelSize: CGSize(width: 900, height: 1600),
            viewportSize: CGSize(width: 1000, height: 700)
        )

        XCTAssertNil(geometry.imagePoint(fromViewPoint: CGPoint(x: 20, y: 350)))
        XCTAssertNotNil(geometry.imagePoint(fromViewPoint: geometry.imageRect.center))
    }

    func testAnchorZoomKeepsSameImagePixelUnderPointer() throws {
        let geometry = MaskEditorGeometry(
            imagePixelSize: CGSize(width: 1600, height: 900),
            viewportSize: CGSize(width: 1000, height: 700),
            zoom: 1,
            pan: CGSize(width: 30, height: -18)
        )
        let anchor = CGPoint(x: 540, y: 300)
        let sourceBefore = try XCTUnwrap(geometry.imagePoint(fromViewPoint: anchor))
        let result = geometry.zoomed(to: 2.25, around: anchor)
        let zoomedGeometry = MaskEditorGeometry(
            imagePixelSize: geometry.imagePixelSize,
            viewportSize: geometry.viewportSize,
            zoom: result.zoom,
            pan: result.pan
        )
        let sourceAfter = try XCTUnwrap(zoomedGeometry.imagePoint(fromViewPoint: anchor))

        XCTAssertEqual(sourceAfter.x, sourceBefore.x, accuracy: 0.000_001)
        XCTAssertEqual(sourceAfter.y, sourceBefore.y, accuracy: 0.000_001)
    }

    func testPanConstraintLeavesPartOfImageReachable() {
        let geometry = MaskEditorGeometry(
            imagePixelSize: CGSize(width: 1000, height: 1000),
            viewportSize: CGSize(width: 500, height: 500),
            zoom: 2
        )
        let constrained = geometry.constrainedPan(CGSize(width: 100_000, height: -100_000))
        var panned = geometry
        panned.pan = constrained

        XCTAssertGreaterThanOrEqual(panned.imageRect.maxX, MaskEditorGeometry.minimumVisibleImageLength)
        XCTAssertLessThanOrEqual(
            panned.imageRect.minY,
            geometry.viewportSize.height - MaskEditorGeometry.minimumVisibleImageLength
        )
    }

    func testPNGRendererKeepsSourcePixelDimensionsAndPaintEraseSemantics() throws {
        let data = try MaskPNGRenderer.data(
            imagePixelSize: CGSize(width: 20, height: 12),
            strokes: [
                MaskEditorStroke(
                    mode: .paint,
                    diameterInPixels: 6,
                    points: [CGPoint(x: 5, y: 5)]
                ),
                MaskEditorStroke(
                    mode: .erase,
                    diameterInPixels: 2,
                    points: [CGPoint(x: 5, y: 5)]
                )
            ]
        )
        let representation = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(representation.pixelsWide, 20)
        XCTAssertEqual(representation.pixelsHigh, 12)
        let erasedCenter = try XCTUnwrap(representation.colorAt(x: 5, y: 5))
        let paintedEdge = try XCTUnwrap(representation.colorAt(x: 7, y: 5))
        let untouched = try XCTUnwrap(representation.colorAt(x: 19, y: 0))
        XCTAssertLessThan(erasedCenter.whiteComponent, 0.3)
        XCTAssertGreaterThan(paintedEdge.whiteComponent, 0.8)
        XCTAssertLessThan(untouched.whiteComponent, 0.1)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
