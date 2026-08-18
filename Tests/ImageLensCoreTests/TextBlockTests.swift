import XCTest
@testable import ImageLensCore

final class TextBlockTests: XCTestCase {
    func testTextBlockPersistsIndependentlyFromPromptModules() throws {
        let timestamp = Date(timeIntervalSince1970: 100)
        let block = TextBlock(
            kind: .note,
            text: "Compare the two compositions",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let node = CanvasNode(
            textBlockID: block.id,
            frame: WorldRect(x: 20, y: 30, width: 280, height: 180)
        )
        let workspace = Workspace(
            title: "Notes",
            textBlocks: [block],
            canvasNodes: [node],
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let decoded = try JSONDecoder().decode(
            Workspace.self,
            from: JSONEncoder().encode(workspace)
        )

        XCTAssertEqual(decoded, workspace)
        XCTAssertTrue(decoded.promptModules.isEmpty)
        XCTAssertEqual(decoded.textBlocks, [block])
        XCTAssertEqual(decoded.canvasNodes.first?.textBlockID, block.id)
    }

    func testLegacyWorkspaceWithoutTextBlocksDecodesEmptyCollection() throws {
        let workspace = Workspace(title: "Legacy")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace))
                as? [String: Any]
        )
        object.removeValue(forKey: "textBlocks")

        let decoded = try JSONDecoder().decode(
            Workspace.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(decoded.textBlocks.isEmpty)
    }
}
