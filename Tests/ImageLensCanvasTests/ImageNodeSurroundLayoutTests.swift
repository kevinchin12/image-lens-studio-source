import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class ImageNodeSurroundLayoutTests: XCTestCase {
    func testTagLaneReservesSpaceForEightStructuredTags() {
        XCTAssertEqual(ImageNodeSurroundLayout.defaultTagStackHeight, 230)
        let layout = ImageNodeSurroundLayout(
            imageFrame: WorldRect(x: 0, y: 0, width: 320, height: 240),
            contentAspectRatio: 1
        )
        XCTAssertEqual(layout.tagLaneFrame.height, 230)
    }

    func testAnalysisCapsuleDoesNotReserveStructuredPromptLaneBeforeSuccess() {
        let imageFrame = WorldRect(x: 0, y: 0, width: 320, height: 240)
        let layout = ImageNodeSurroundLayout(
            imageFrame: imageFrame,
            contentAspectRatio: 4.0 / 3.0,
            includesHeaderChrome: true,
            includesAnalysisChrome: true,
            includesStructuredPromptChrome: false
        )

        XCTAssertTrue(layout.includesAnalysisChrome)
        XCTAssertFalse(layout.includesStructuredPromptChrome)
        XCTAssertNotEqual(layout.summaryFrame, .zero)
        XCTAssertEqual(layout.tagLaneFrame, .zero)
        XCTAssertEqual(layout.shellFrame.width, imageFrame.width, accuracy: 0.0001)
    }

    func testPortraitContentAnchorsChromeToNarrowDisplayedImageWithoutOverlap() {
        let layout = ImageNodeSurroundLayout(
            imageFrame: WorldRect(x: 100, y: 200, width: 320, height: 240),
            contentAspectRatio: 9.0 / 16.0
        )

        XCTAssertEqual(layout.persistedImageFrame, WorldRect(x: 100, y: 200, width: 320, height: 240))
        XCTAssertEqual(layout.displayedImageFrame.width, 135, accuracy: 0.0001)
        XCTAssertEqual(layout.displayedImageFrame.height, 240, accuracy: 0.0001)
        XCTAssertEqual(layout.displayedImageFrame.minX, 192.5, accuracy: 0.0001)
        XCTAssertEqual(layout.headerFrame.minX, layout.displayedImageFrame.minX, accuracy: 0.0001)
        XCTAssertEqual(layout.headerFrame.width, layout.displayedImageFrame.width, accuracy: 0.0001)
        XCTAssertEqual(
            layout.displayedImageFrame.minY - layout.headerFrame.maxY,
            ImageNodeSurroundLayout.defaultRailGap,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            layout.summaryFrame.minY - layout.displayedImageFrame.maxY,
            ImageNodeSurroundLayout.defaultRailGap,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            layout.tagLaneFrame.minX - layout.displayedImageFrame.maxX,
            ImageNodeSurroundLayout.defaultTagGap,
            accuracy: 0.0001
        )
        assertChromeDoesNotCoverImage(layout)
    }

    func testSquareAndLandscapeContentKeepAllSurroundingChromeOutsideDisplayedPixels() {
        let imageFrame = WorldRect(x: -20, y: 30, width: 320, height: 240)
        for aspectRatio in [1.0, 16.0 / 9.0] {
            let layout = ImageNodeSurroundLayout(
                imageFrame: imageFrame,
                contentAspectRatio: aspectRatio
            )

            assertChromeDoesNotCoverImage(layout)
            XCTAssertTrue(layout.shellFrame.contains(layout.persistedImageFrame))
            XCTAssertTrue(layout.shellFrame.contains(layout.headerFrame))
            XCTAssertTrue(layout.shellFrame.contains(layout.summaryFrame))
            XCTAssertTrue(layout.shellFrame.contains(layout.tagLaneFrame))
        }
    }

    func testShellEnvelopeDoesNotChangeWhenDecodedImageAspectRatioArrives() {
        let imageFrame = WorldRect(x: 0, y: 0, width: 320, height: 240)
        let placeholder = ImageNodeSurroundLayout(imageFrame: imageFrame, contentAspectRatio: nil)
        let portrait = ImageNodeSurroundLayout(imageFrame: imageFrame, contentAspectRatio: 9.0 / 16.0)
        let landscape = ImageNodeSurroundLayout(imageFrame: imageFrame, contentAspectRatio: 16.0 / 9.0)

        XCTAssertEqual(placeholder.shellFrame, portrait.shellFrame)
        XCTAssertEqual(placeholder.shellFrame, landscape.shellFrame)
        XCTAssertEqual(placeholder.displayedImageFrame, imageFrame)
    }

    func testPureImageModeOmitsEveryMetadataRail() {
        let imageFrame = WorldRect(x: 40, y: 60, width: 320, height: 240)
        let layout = ImageNodeSurroundLayout(
            imageFrame: imageFrame,
            contentAspectRatio: 4.0 / 3.0,
            includesHeaderChrome: false,
            includesAnalysisChrome: false
        )

        XCTAssertFalse(layout.includesHeaderChrome)
        XCTAssertFalse(layout.includesAnalysisChrome)
        XCTAssertEqual(layout.headerFrame, .zero)
        XCTAssertEqual(layout.summaryFrame, .zero)
        XCTAssertEqual(layout.tagLaneFrame, .zero)
        XCTAssertEqual(layout.shellFrame, imageFrame)
        XCTAssertEqual(layout.displayedImageFrame, imageFrame)
    }

    func testConnectionAnchorsFollowDisplayedPixelsInsteadOfHiddenChrome() {
        let imageFrame = WorldRect(x: 100, y: 200, width: 320, height: 240)
        for aspectRatio in [9.0 / 16.0, 1.0, 16.0 / 9.0] {
            let visibleChrome = ImageNodeSurroundLayout(
                imageFrame: imageFrame,
                contentAspectRatio: aspectRatio,
                includesHeaderChrome: true,
                includesAnalysisChrome: true
            )
            let hiddenChrome = ImageNodeSurroundLayout(
                imageFrame: imageFrame,
                contentAspectRatio: aspectRatio,
                includesHeaderChrome: false,
                includesAnalysisChrome: false
            )

            XCTAssertEqual(
                visibleChrome.leadingImageConnectionAnchor,
                hiddenChrome.leadingImageConnectionAnchor
            )
            XCTAssertEqual(
                visibleChrome.trailingImageConnectionAnchor,
                hiddenChrome.trailingImageConnectionAnchor
            )
            XCTAssertEqual(
                visibleChrome.trailingImageConnectionAnchor.x,
                visibleChrome.displayedImageFrame.maxX,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                visibleChrome.trailingImageConnectionAnchor.y,
                visibleChrome.displayedImageFrame.minY
                    + visibleChrome.displayedImageFrame.height / 2,
                accuracy: 0.0001
            )
            XCTAssertLessThan(
                visibleChrome.trailingImageConnectionAnchor.x,
                visibleChrome.tagLaneFrame.maxX
            )
        }
    }

    private func assertChromeDoesNotCoverImage(
        _ layout: ImageNodeSurroundLayout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            layout.headerFrame.intersects(layout.displayedImageFrame),
            file: file,
            line: line
        )
        XCTAssertFalse(
            layout.summaryFrame.intersects(layout.displayedImageFrame),
            file: file,
            line: line
        )
        XCTAssertFalse(
            layout.tagLaneFrame.intersects(layout.displayedImageFrame),
            file: file,
            line: line
        )
    }
}
