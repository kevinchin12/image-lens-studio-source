import Foundation
import XCTest
@testable import ImageLensCore

final class CanvasGenerationGroupTests: XCTestCase {
    func testGroupRoundTripsWithoutBecomingANewCanvasNodeKind() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let group = CanvasGenerationGroup(
            id: CanvasGenerationGroupID(
                UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
            ),
            generatorID: GeneratorID(
                UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
            ),
            name: "最终候选",
            memberNodeIDs: [
                CanvasNodeID(UUID(uuidString: "30000000-0000-0000-0000-000000000003")!),
                CanvasNodeID(UUID(uuidString: "30000000-0000-0000-0000-000000000004")!)
            ],
            origin: WorldPoint(x: 640, y: 360),
            isCollapsed: true,
            columns: 3,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(CanvasGenerationGroup.self, from: data)

        XCTAssertEqual(decoded, group)
        XCTAssertEqual(decoded.name, "最终候选")
        XCTAssertEqual(decoded.columns, 3)
        XCTAssertEqual(decoded.memberNodeIDs.count, 2)
        XCTAssertEqual(CanvasNodeKind.allCases, [.image, .module, .text, .recipe, .generation])
    }

    func testGroupNormalizesColumnCountToAtLeastOne() {
        let group = CanvasGenerationGroup(
            generatorID: GeneratorID(),
            origin: .zero,
            columns: 0
        )

        XCTAssertEqual(group.columns, 1)
    }

    func testGroupMayPersistAfterGeneratorConfigurationIsDeleted() throws {
        let group = CanvasGenerationGroup(
            generatorID: nil,
            name: "保留结果",
            memberNodeIDs: [CanvasNodeID()],
            origin: .zero
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(CanvasGenerationGroup.self, from: data)

        XCTAssertNil(decoded.generatorID)
        XCTAssertEqual(decoded.name, "保留结果")
        XCTAssertEqual(decoded.memberNodeIDs, group.memberNodeIDs)
    }

    func testWorkspacePersistsGenerationGroups() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let group = CanvasGenerationGroup(
            generatorID: GeneratorID(),
            memberNodeIDs: [CanvasNodeID()],
            origin: WorldPoint(x: 120, y: 240),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let workspace = Workspace(
            title: "Grouped results",
            generationGroups: [group],
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)

        XCTAssertEqual(decoded, workspace)
        XCTAssertEqual(decoded.generationGroups, [group])
        XCTAssertEqual(decoded.schemaVersion, Workspace.currentSchemaVersion)
    }

    func testLegacyWorkspaceWithoutGenerationGroupsDecodesWithEmptyCollection() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let workspace = Workspace(
            title: "Legacy workspace",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let encoded = try JSONEncoder().encode(workspace)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "generationGroups")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Workspace.self, from: legacyData)

        XCTAssertTrue(decoded.generationGroups.isEmpty)
        XCTAssertEqual(decoded.title, workspace.title)
        XCTAssertEqual(decoded.schemaVersion, Workspace.currentSchemaVersion)
    }

    func testLegacyGenerationGroupWithoutNameDecodesWithNilName() throws {
        let group = CanvasGenerationGroup(
            generatorID: GeneratorID(),
            name: "生成结果 1",
            memberNodeIDs: [CanvasNodeID()],
            origin: .zero
        )
        let encoded = try JSONEncoder().encode(group)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "name")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CanvasGenerationGroup.self, from: legacyData)

        XCTAssertNil(decoded.name)
        XCTAssertEqual(decoded.generatorID, group.generatorID)
    }
}
