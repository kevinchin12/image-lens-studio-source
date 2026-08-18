import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class CanvasNodePlacementPolicyTests: XCTestCase {
    func testDefaultSizesCoverAllNodeKinds() {
        let policy = CanvasNodePlacementPolicy.studioDefault

        XCTAssertEqual(policy.defaultSize(for: .image), WorldSize(width: 320, height: 240))
        XCTAssertEqual(policy.defaultSize(for: .module), WorldSize(width: 280, height: 160))
        XCTAssertEqual(policy.defaultSize(for: .text), WorldSize(width: 280, height: 180))
        XCTAssertEqual(policy.defaultSize(for: .recipe), WorldSize(width: 320, height: 200))
        XCTAssertEqual(policy.defaultSize(for: .generation), WorldSize(width: 440, height: 426))
    }

    func testImportedImagesCascadePastOccupiedOriginAndAboveExistingZOrder() {
        let policy = CanvasNodePlacementPolicy.studioDefault
        let origin = WorldPoint(x: 100, y: 200)
        let existingAtOrigin = CanvasNode(
            recipeID: RecipeID(),
            frame: WorldRect(origin: origin, size: WorldSize(width: 320, height: 200)),
            zIndex: 3
        )
        let existingTopNode = CanvasNode(
            generationID: GenerationID(),
            frame: WorldRect(x: -500, y: -500, width: 320, height: 260),
            zIndex: 9
        )
        let assetIDs = [AssetID(), AssetID()]
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let nodes = policy.placeImportedImages(
            assetIDs,
            startingAt: origin,
            existingNodes: [existingAtOrigin, existingTopNode],
            createdAt: timestamp
        )

        XCTAssertEqual(nodes.map(\.imageAssetID), assetIDs.map(Optional.some))
        XCTAssertEqual(nodes.map(\.frame.origin), [
            WorldPoint(x: 148, y: 248),
            WorldPoint(x: 196, y: 296)
        ])
        XCTAssertEqual(nodes.map(\.frame.size), Array(repeating: WorldSize(width: 320, height: 240), count: 2))
        XCTAssertEqual(nodes.map(\.zIndex), [10, 11])
        XCTAssertEqual(nodes.map(\.createdAt), [timestamp, timestamp])
    }

    func testCanonicalNodeProjectsToCullingPlacement() {
        let nodeID = CanvasNodeID(UUID(uuidString: "30000000-0000-0000-0000-000000000003")!)
        let node = CanvasNode(
            id: nodeID,
            promptModuleID: PromptModuleID(),
            frame: WorldRect(x: 20, y: 30, width: 280, height: 160),
            zIndex: 4
        )

        let placement = CanvasNodePlacement(node: node)

        XCTAssertEqual(placement.id, nodeID.rawValue)
        XCTAssertEqual(placement.frame, node.frame)
        XCTAssertEqual(placement.zIndex, node.zIndex)
    }
}
