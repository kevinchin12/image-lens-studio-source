import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class FixedWidthImageGridPlacementTests: XCTestCase {
    func testPortraitSquareAndLandscapeKeepTheSameWidthWithPixelAccurateHeights() {
        let policy = FixedWidthImageGridPlacement()
        let items = [
            item(width: 768, height: 1_376),
            item(width: 1_024, height: 1_024),
            item(width: 1_376, height: 768)
        ]

        let nodes = policy.place(
            items,
            startingAt: .zero,
            columns: 3,
            gap: WorldSize(width: 40, height: 40)
        )

        XCTAssertEqual(nodes.map(\.frame.width), [320, 320, 320])
        XCTAssertEqual(nodes[0].frame.height, 320 * 1_376.0 / 768.0, accuracy: 0.0001)
        XCTAssertEqual(nodes[1].frame.height, 320, accuracy: 0.0001)
        XCTAssertEqual(nodes[2].frame.height, 320 * 768.0 / 1_376.0, accuracy: 0.0001)
        XCTAssertEqual(nodes.map(\.imageAssetID), items.map { Optional($0.assetID) })
    }

    func testFixedWidthFramesMakeTheVisiblePixelsFillTheSameWidth() {
        let policy = FixedWidthImageGridPlacement()
        let pixelSizes = [
            PixelSize(width: 768, height: 1_376),
            PixelSize(width: 1_024, height: 1_024),
            PixelSize(width: 1_376, height: 768)
        ]

        for pixelSize in pixelSizes {
            let frame = WorldRect(origin: .zero, size: policy.size(for: pixelSize))
            let layout = ImageNodeSurroundLayout(
                imageFrame: frame,
                contentAspectRatio: Double(pixelSize.width) / Double(pixelSize.height)
            )

            XCTAssertEqual(layout.displayedImageFrame.width, 320, accuracy: 0.0001)
            XCTAssertEqual(layout.displayedImageFrame.height, frame.height, accuracy: 0.0001)
        }
    }

    func testMissingOrInvalidPixelSizeUsesFallbackHeight() {
        let policy = FixedWidthImageGridPlacement(targetWidth: 320, fallbackHeight: 240)

        XCTAssertEqual(policy.size(for: nil), WorldSize(width: 320, height: 240))
        XCTAssertEqual(
            policy.size(for: PixelSize(width: 0, height: 1_024)),
            WorldSize(width: 320, height: 240)
        )
        XCTAssertEqual(
            policy.size(for: PixelSize(width: 1_024, height: 0)),
            WorldSize(width: 320, height: 240)
        )
    }

    func testTwoColumnRowsUseTallestItemAndContinueExistingZIndexWithoutOverlap() {
        let policy = FixedWidthImageGridPlacement()
        let origin = WorldPoint(x: 100, y: 200)
        let gap = WorldSize(width: 40, height: 32)
        let items = [
            item(width: 768, height: 1_376),
            item(width: 1_376, height: 768),
            item(width: 1_024, height: 1_024),
            FixedWidthImageGridPlacement.Item(assetID: AssetID(), pixelSize: nil)
        ]
        let existing = CanvasNode(
            promptModuleID: PromptModuleID(),
            frame: WorldRect(x: -100, y: -100, width: 280, height: 160),
            zIndex: 9
        )

        let nodes = policy.place(
            items,
            startingAt: origin,
            columns: 2,
            gap: gap,
            existingNodes: [existing],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let firstRowHeight = 320 * 1_376.0 / 768.0
        XCTAssertEqual(nodes.map(\.zIndex), [10, 11, 12, 13])
        XCTAssertEqual(nodes[0].frame.origin, origin)
        XCTAssertEqual(nodes[1].frame.origin.x, origin.x + 320 + gap.width, accuracy: 0.0001)
        XCTAssertEqual(nodes[1].frame.origin.y, origin.y, accuracy: 0.0001)
        XCTAssertEqual(nodes[2].frame.origin.x, origin.x, accuracy: 0.0001)
        XCTAssertEqual(nodes[2].frame.origin.y, origin.y + firstRowHeight + gap.height, accuracy: 0.0001)
        XCTAssertEqual(nodes[3].frame.origin.x, origin.x + 320 + gap.width, accuracy: 0.0001)
        XCTAssertEqual(nodes[3].frame.origin.y, nodes[2].frame.origin.y, accuracy: 0.0001)

        for firstIndex in nodes.indices {
            for secondIndex in nodes.indices where secondIndex > firstIndex {
                XCTAssertFalse(nodes[firstIndex].frame.intersects(nodes[secondIndex].frame))
            }
        }
    }

    private func item(width: Int, height: Int) -> FixedWidthImageGridPlacement.Item {
        FixedWidthImageGridPlacement.Item(
            assetID: AssetID(),
            pixelSize: PixelSize(width: width, height: height)
        )
    }
}
