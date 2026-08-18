import Foundation
import XCTest
@testable import ImageLensCore

final class CanvasNodeTests: XCTestCase {
    func testStrongNodeIDAndTypedAssociationRoundTripThroughJSON() throws {
        let nodeID = CanvasNodeID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
        let assetID = AssetID(UUID(uuidString: "20000000-0000-0000-0000-000000000002")!)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let node = CanvasNode(
            id: nodeID,
            imageAssetID: assetID,
            frame: WorldRect(x: 400, y: 300, width: -320, height: -240),
            zIndex: 7,
            createdAt: timestamp
        )

        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(CanvasNode.self, from: data)

        XCTAssertEqual(decoded, node)
        XCTAssertEqual(decoded.id, nodeID)
        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.imageAssetID, assetID)
        XCTAssertNil(decoded.promptModuleID)
        XCTAssertEqual(decoded.frame, WorldRect(x: 80, y: 60, width: 320, height: 240))
    }

    func testTypedInitializersCoverFiniteCanvasVocabulary() {
        let frame = WorldRect(x: 0, y: 0, width: 10, height: 10)
        let moduleID = PromptModuleID()
        let recipeID = RecipeID()
        let textBlockID = TextBlockID()
        let generationID = GenerationID()

        let module = CanvasNode(promptModuleID: moduleID, frame: frame)
        let text = CanvasNode(textBlockID: textBlockID, frame: frame)
        let recipe = CanvasNode(recipeID: recipeID, frame: frame)
        let generation = CanvasNode(generationID: generationID, frame: frame)

        XCTAssertEqual(module.kind, .module)
        XCTAssertEqual(module.promptModuleID, moduleID)
        XCTAssertEqual(text.kind, .text)
        XCTAssertEqual(text.textBlockID, textBlockID)
        XCTAssertEqual(recipe.kind, .recipe)
        XCTAssertEqual(recipe.recipeID, recipeID)
        XCTAssertEqual(generation.kind, .generation)
        XCTAssertEqual(generation.generationID, generationID)
    }

    func testWorkspacePersistsCanvasNodesAtCurrentSchemaVersion() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let node = CanvasNode(
            recipeID: RecipeID(),
            frame: WorldRect(x: 20, y: 30, width: 320, height: 200),
            zIndex: 2,
            createdAt: timestamp
        )
        let workspace = Workspace(
            title: "Canvas workspace",
            canvasNodes: [node],
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)

        XCTAssertEqual(decoded, workspace)
        XCTAssertEqual(decoded.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(decoded.canvasNodes, [node])
    }
}
