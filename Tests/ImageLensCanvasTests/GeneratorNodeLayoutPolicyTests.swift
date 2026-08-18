import XCTest
@testable import ImageLensCanvas

final class GeneratorNodeLayoutPolicyTests: XCTestCase {
    func testOutputShelfExpandsOnlyAbovePersistedGeneratorFrame() {
        let frame = WorldRect(x: 100, y: 200, width: 440, height: 426)

        XCTAssertEqual(
            GeneratorNodeLayoutPolicy.shellFrame(around: frame, outputBatchCount: 0),
            frame
        )

        let shell = GeneratorNodeLayoutPolicy.shellFrame(around: frame, outputBatchCount: 2)
        let expectedShelfHeight = 54.0 + 10.0
        XCTAssertEqual(shell.minX, frame.minX)
        XCTAssertEqual(shell.minY, frame.minY - expectedShelfHeight)
        XCTAssertEqual(
            shell.width,
            frame.width + GeneratorNodeLayoutPolicy.outputReferenceHandleGutterWidth
        )
        XCTAssertEqual(shell.maxY, frame.maxY)
        XCTAssertEqual(
            GeneratorNodeLayoutPolicy.shellFrame(around: frame, outputBatchCount: 9),
            shell,
            "历史越多只增加横向内容，不应把结果架堆成多行"
        )

        let rail = try! XCTUnwrap(
            GeneratorNodeLayoutPolicy.outputRailFrame(around: frame, outputBatchCount: 2)
        )
        XCTAssertEqual(rail.minX, frame.minX + GeneratorNodeLayoutPolicy.horizontalPadding)
        XCTAssertEqual(rail.width, frame.width - GeneratorNodeLayoutPolicy.horizontalPadding * 2)
        XCTAssertEqual(rail.height, GeneratorNodeLayoutPolicy.outputThumbnailHeight)
        XCTAssertEqual(
            frame.minY - rail.maxY,
            GeneratorNodeLayoutPolicy.outputShelfSpacing
        )
        XCTAssertNil(
            GeneratorNodeLayoutPolicy.outputRailFrame(around: frame, outputBatchCount: 0)
        )
    }

    func testOutputRailAndBodyKeepTheirGapAtEveryCanvasScale() throws {
        let frame = WorldRect(x: 100, y: 200, width: 440, height: 426)
        let rail = try XCTUnwrap(
            GeneratorNodeLayoutPolicy.outputRailFrame(around: frame, outputBatchCount: 3)
        )

        for scale in [0.2, 0.5, 1.0, 2.0, 4.0] {
            let viewport = ViewportTransform(scale: scale, translation: .zero)
            let railRect = viewport.viewRect(for: rail)
            let bodyRect = viewport.viewRect(for: frame)

            XCTAssertEqual(
                bodyRect.origin.y - (railRect.origin.y + railRect.size.height),
                GeneratorNodeLayoutPolicy.outputShelfSpacing * scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                railRect.origin.x - bodyRect.origin.x,
                GeneratorNodeLayoutPolicy.horizontalPadding * scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                bodyRect.size.width - railRect.size.width,
                GeneratorNodeLayoutPolicy.horizontalPadding * 2 * scale,
                accuracy: 0.001
            )
        }
    }

    func testDefaultGeneratorWidthProducesComposerContentWidth() {
        let layout = GeneratorNodeLayoutPolicy(nodeWidth: GeneratorNodeLayoutPolicy.defaultWidth)

        XCTAssertEqual(layout.contentWidth, 424)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.defaultWidth, 440)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.minimumWidth, 380)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.collapsedHeight, 426)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.controlHeight, 26)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.inputRowHeight, 26)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.mediaStageHeight, 238.5)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.footerHeight, 38)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.imageEditSummaryHeight, 34)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.imageEditSummarySpacing, 7)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.imageEditSupplementaryHeight, 41)
        XCTAssertLessThan(GeneratorNodeLayoutPolicy.referenceAnchorY, GeneratorNodeLayoutPolicy.inputAnchorY)
        XCTAssertLessThan(GeneratorNodeLayoutPolicy.inputAnchorY, GeneratorNodeLayoutPolicy.collapsedHeight)
    }

    func testGeneratorHeightNormalizationIsMonotonicAndIdempotent() {
        XCTAssertEqual(GeneratorNodeLayoutPolicy.normalizedHeight(260), 426)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.normalizedHeight(400), 426)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.normalizedHeight(460), 460)
        XCTAssertEqual(GeneratorNodeLayoutPolicy.normalizedHeight(560), 426)
        XCTAssertEqual(
            GeneratorNodeLayoutPolicy.normalizedHeight(
                GeneratorNodeLayoutPolicy.normalizedHeight(260)
            ),
            426
        )
        XCTAssertEqual(GeneratorNodeLayoutPolicy.normalizedHeight(.nan), 426)
    }

    func testMediaReferenceAnchorTracksTheFittedGeneratedImageEdge() {
        let node = WorldRect(x: 100, y: 200, width: 440, height: 426)

        let wideFrame = GeneratorNodeLayoutPolicy.mediaContentFrame(
            in: node,
            contentAspectRatio: 16.0 / 9.0
        )
        XCTAssertEqual(wideFrame.minX, 108, accuracy: 0.001)
        XCTAssertEqual(wideFrame.width, 424, accuracy: 0.001)
        XCTAssertEqual(wideFrame.height, 238.5, accuracy: 0.001)
        XCTAssertEqual(
            GeneratorNodeLayoutPolicy.mediaReferenceAnchor(
                in: node,
                contentAspectRatio: 16.0 / 9.0
            ),
            WorldPoint(x: wideFrame.maxX, y: wideFrame.minY + wideFrame.height / 2)
        )
        XCTAssertEqual(
            GeneratorNodeLayoutPolicy.outputReferenceHandleCenter(
                in: node,
                contentAspectRatio: 16.0 / 9.0
            ),
            WorldPoint(
                x: node.maxX
                    + GeneratorNodeLayoutPolicy.outputReferenceHandleGap
                    + GeneratorNodeLayoutPolicy.outputReferenceHandleDiameter / 2,
                y: wideFrame.minY + wideFrame.height / 2
            )
        )

        let squareFrame = GeneratorNodeLayoutPolicy.mediaContentFrame(
            in: node,
            contentAspectRatio: 1
        )
        XCTAssertEqual(squareFrame.width, 238.5, accuracy: 0.001)
        XCTAssertEqual(squareFrame.height, 238.5, accuracy: 0.001)
        XCTAssertEqual(squareFrame.minX, 200.75, accuracy: 0.001)
        XCTAssertEqual(squareFrame.minY, 208, accuracy: 0.001)
    }

    func testMediaReferenceAnchorFallsBackToSixteenByNine() {
        let node = WorldRect(x: 0, y: 0, width: 440, height: 426)
        XCTAssertEqual(
            GeneratorNodeLayoutPolicy.mediaReferenceAnchor(
                in: node,
                contentAspectRatio: nil
            ),
            GeneratorNodeLayoutPolicy.mediaReferenceAnchor(
                in: node,
                contentAspectRatio: 16.0 / 9.0
            )
        )
    }

    func testOutputReferenceHandleStaysOutsideTheNodeForEveryAspectRatio() {
        let node = WorldRect(x: 100, y: 200, width: 440, height: 426)
        let shell = GeneratorNodeLayoutPolicy.shellFrame(around: node, outputBatchCount: 1)
        let expectedCenterX = node.maxX
            + GeneratorNodeLayoutPolicy.outputReferenceHandleGap
            + GeneratorNodeLayoutPolicy.outputReferenceHandleDiameter / 2

        for ratio in [16.0 / 9.0, 1.0, 9.0 / 16.0] {
            let media = GeneratorNodeLayoutPolicy.mediaContentFrame(
                in: node,
                contentAspectRatio: ratio
            )
            let center = GeneratorNodeLayoutPolicy.outputReferenceHandleCenter(
                in: node,
                contentAspectRatio: ratio
            )

            XCTAssertEqual(center.y, media.minY + media.height / 2, accuracy: 0.001)
            XCTAssertEqual(center.x, expectedCenterX, accuracy: 0.001)
            XCTAssertEqual(
                GeneratorNodeLayoutPolicy.outputReferenceNodeEdgeAnchor(
                    in: node,
                    contentAspectRatio: ratio
                ),
                WorldPoint(x: node.maxX, y: media.minY + media.height / 2)
            )
            XCTAssertGreaterThanOrEqual(
                center.x - GeneratorNodeLayoutPolicy.outputReferenceHandleHitDiameter / 2,
                node.maxX
            )
            XCTAssertEqual(
                center.x + GeneratorNodeLayoutPolicy.outputReferenceHandleHitDiameter / 2,
                shell.maxX,
                accuracy: 0.001
            )
        }

        let portraitMedia = GeneratorNodeLayoutPolicy.mediaContentFrame(
            in: node,
            contentAspectRatio: 9.0 / 16.0
        )
        XCTAssertLessThan(portraitMedia.maxX, node.maxX)
        XCTAssertGreaterThan(expectedCenterX, node.maxX)
    }

    func testNarrowGeneratorKeepsMediaAlignedToTheSharedTopInset() {
        let node = WorldRect(x: 100, y: 200, width: 380, height: 426)
        let frame = GeneratorNodeLayoutPolicy.mediaContentFrame(
            in: node,
            contentAspectRatio: 16.0 / 9.0
        )

        XCTAssertEqual(frame.minX, node.minX + GeneratorNodeLayoutPolicy.horizontalPadding)
        XCTAssertEqual(frame.minY, node.minY + GeneratorNodeLayoutPolicy.horizontalPadding)
        XCTAssertEqual(frame.width, 364, accuracy: 0.001)
        XCTAssertEqual(frame.height, 204.75, accuracy: 0.001)
        XCTAssertEqual(
            GeneratorNodeLayoutPolicy.fittedMediaStageHeight(
                nodeWidth: node.width,
                contentAspectRatio: 16.0 / 9.0
            ),
            frame.height,
            accuracy: 0.001
        )
    }
}
