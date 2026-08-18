import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class GenerationGroupLayoutPolicyTests: XCTestCase {
    private let origin = WorldPoint(x: 100, y: 200)

    func testOneMemberStartsBelowHeaderAndPreservesAspectRatioAtFixedWidth() throws {
        let policy = GenerationGroupLayoutPolicy()
        let member = imageNode(x: -400, y: 900, width: 1_600, height: 900)

        let layout = policy.layout(
            members: [member],
            origin: origin,
            columns: 2,
            isCollapsed: false
        )

        let frame = try XCTUnwrap(layout.frame(for: member.id))
        XCTAssertEqual(frame.origin, WorldPoint(x: 124, y: 284))
        XCTAssertEqual(frame.width, 320, accuracy: 0.0001)
        XCTAssertEqual(frame.height, 180, accuracy: 0.0001)
        XCTAssertEqual(layout.headerFrame, WorldRect(x: 124, y: 224, width: 320, height: 44))
        XCTAssertEqual(layout.contentFrame, frame)
        XCTAssertEqual(layout.bounds, WorldRect(x: 100, y: 200, width: 368, height: 288))
    }

    func testTwoMembersUseOneTidyRow() throws {
        let policy = GenerationGroupLayoutPolicy()
        let members = [
            imageNode(width: 1_600, height: 900),
            imageNode(width: 1_024, height: 1_024)
        ]

        let layout = policy.layout(
            members: members,
            origin: origin,
            columns: 2,
            isCollapsed: false
        )

        XCTAssertEqual(try XCTUnwrap(layout.frame(for: members[0].id)).origin, WorldPoint(x: 124, y: 284))
        XCTAssertEqual(try XCTUnwrap(layout.frame(for: members[1].id)).origin, WorldPoint(x: 476, y: 284))
        XCTAssertEqual(layout.contentFrame, WorldRect(x: 124, y: 284, width: 672, height: 320))
        XCTAssertEqual(layout.bounds, WorldRect(x: 100, y: 200, width: 720, height: 428))
    }

    func testThreeMixedAspectRatiosUseTallestMemberToAdvanceNextRow() throws {
        let policy = GenerationGroupLayoutPolicy()
        let members = [
            imageNode(width: 1_600, height: 900), // 16:9 -> 180
            imageNode(width: 1_024, height: 1_024), // 1:1 -> 320
            imageNode(width: 900, height: 1_600) // 9:16 -> 568.89
        ]

        let layout = policy.layout(
            members: members,
            origin: origin,
            columns: 2,
            isCollapsed: false
        )

        let first = try XCTUnwrap(layout.frame(for: members[0].id))
        let second = try XCTUnwrap(layout.frame(for: members[1].id))
        let third = try XCTUnwrap(layout.frame(for: members[2].id))

        XCTAssertEqual(first.height, 180, accuracy: 0.0001)
        XCTAssertEqual(second.height, 320, accuracy: 0.0001)
        XCTAssertEqual(third.height, 320 * 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(third.origin, WorldPoint(x: 124, y: 636))
        XCTAssertEqual(layout.contentFrame.height, 320 + 32 + (320 * 16.0 / 9.0), accuracy: 0.0001)
        XCTAssertEqual(layout.bounds.height, 24 + 44 + 16 + layout.contentFrame.height + 24, accuracy: 0.0001)
    }

    func testFourMembersCreateTwoRowsWithoutOverlap() {
        let policy = GenerationGroupLayoutPolicy()
        let members = [
            imageNode(width: 1_600, height: 900),
            imageNode(width: 1_024, height: 1_024),
            imageNode(width: 900, height: 1_600),
            imageNode(width: 1_600, height: 900)
        ]

        let layout = policy.layout(
            members: members,
            origin: origin,
            columns: 2,
            isCollapsed: false
        )
        let frames = layout.memberPlacements.map(\.frame)

        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames[0].origin, WorldPoint(x: 124, y: 284))
        XCTAssertEqual(frames[1].origin, WorldPoint(x: 476, y: 284))
        XCTAssertEqual(frames[2].origin, WorldPoint(x: 124, y: 636))
        XCTAssertEqual(frames[3].origin, WorldPoint(x: 476, y: 636))
        XCTAssertEqual(layout.contentFrame.height, 320 + 32 + (320 * 16.0 / 9.0), accuracy: 0.0001)

        for firstIndex in frames.indices {
            for secondIndex in frames.indices where secondIndex > firstIndex {
                XCTAssertFalse(frames[firstIndex].intersects(frames[secondIndex]))
            }
        }

        let chromeShells = frames.map {
            ImageNodeSurroundLayout(
                imageFrame: $0,
                contentAspectRatio: nil,
                includesHeaderChrome: false,
                includesAnalysisChrome: false
            ).shellFrame
        }
        for firstIndex in chromeShells.indices {
            XCTAssertTrue(layout.bounds.contains(chromeShells[firstIndex]))
            for secondIndex in chromeShells.indices where secondIndex > firstIndex {
                XCTAssertFalse(
                    chromeShells[firstIndex].intersects(chromeShells[secondIndex]),
                    "hover metadata for neighboring group members must not overlap"
                )
            }
        }
    }

    func testCollapsedLayoutUsesCardSizeAndHidesMemberFrames() {
        let policy = GenerationGroupLayoutPolicy(
            contentPadding: 20,
            headerHeight: 40,
            collapsedCardSize: WorldSize(width: 300, height: 88)
        )
        let members = [
            imageNode(width: 1_600, height: 900),
            imageNode(width: 900, height: 1_600)
        ]

        let layout = policy.layout(
            members: members,
            origin: origin,
            columns: 2,
            isCollapsed: true
        )

        XCTAssertTrue(layout.isCollapsed)
        XCTAssertTrue(layout.memberPlacements.isEmpty)
        XCTAssertTrue(layout.memberFrames.isEmpty)
        XCTAssertEqual(layout.bounds, WorldRect(x: 100, y: 200, width: 300, height: 88))
        XCTAssertEqual(layout.headerFrame, WorldRect(x: 120, y: 220, width: 260, height: 40))
        XCTAssertEqual(layout.contentFrame, .zero)
    }

    func testInvalidMemberFrameUsesFallbackHeightAndRequestedColumnsAreClamped() throws {
        let policy = GenerationGroupLayoutPolicy(
            memberWidth: 300,
            fallbackMemberHeight: 225,
            collapsedCardSize: WorldSize(width: 280, height: 96)
        )
        let member = imageNode(width: 0, height: 0)

        let layout = policy.layout(
            members: [member],
            origin: .zero,
            columns: 0,
            isCollapsed: false
        )

        let frame = try XCTUnwrap(layout.frame(for: member.id))
        XCTAssertEqual(frame.size, WorldSize(width: 300, height: 225))
        XCTAssertEqual(layout.contentFrame.width, 300)
    }

    private func imageNode(
        x: Double = 0,
        y: Double = 0,
        width: Double,
        height: Double
    ) -> CanvasNode {
        CanvasNode(
            imageAssetID: AssetID(),
            frame: WorldRect(x: x, y: y, width: width, height: height)
        )
    }
}
