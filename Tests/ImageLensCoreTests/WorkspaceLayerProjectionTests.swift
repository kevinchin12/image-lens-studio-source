import Foundation
import XCTest
@testable import ImageLensCore

final class WorkspaceLayerProjectionTests: XCTestCase {
    private let target = CompileTarget(
        providerID: "test",
        modelID: "image-model",
        languageCode: "zh-Hans"
    )

    func testProjectsEveryCanvasOccurrenceIntoTheExpectedCategory() {
        let source = asset(id: 1, kind: .source, name: "客厅参考.jpg", width: 1200, height: 800)
        let generated = asset(
            id: 2,
            kind: .generated,
            name: "generation-uuid.jpg",
            width: 1024,
            height: 1024
        )
        let module = PromptModule(
            id: PromptModuleID(uuid(3)),
            role: .visual(.subject),
            content: "一枚悬浮的金色纪念币",
            evidence: .userProvided
        )
        let recipe = Recipe(
            id: RecipeID(uuid(4)),
            name: "金币海报组合",
            bindings: [
                RecipeInputBinding(
                    moduleID: module.id,
                    role: module.role,
                    order: 0,
                    priority: .primary
                )
            ],
            target: target
        )
        let generator = Generator(
            id: GeneratorID(uuid(5)),
            name: "金币海报",
            recipeID: recipe.id,
            target: target,
            parameters: GenerationParameters(aspectRatio: "1:1")
        )

        let sourceNode = imageNode(id: 11, assetID: source.id, zIndex: 1)
        let generatedNode = imageNode(id: 12, assetID: generated.id, zIndex: 2)
        let moduleNode = CanvasNode(
            id: CanvasNodeID(uuid(13)),
            promptModuleID: module.id,
            frame: frame,
            zIndex: 3,
            createdAt: date(13)
        )
        let recipeNode = CanvasNode(
            id: CanvasNodeID(uuid(14)),
            recipeID: recipe.id,
            frame: frame,
            zIndex: 4,
            createdAt: date(14)
        )
        let generatorNode = CanvasNode(
            id: CanvasNodeID(uuid(15)),
            generatorID: generator.id,
            frame: frame,
            zIndex: 5,
            createdAt: date(15)
        )
        let group = CanvasGenerationGroup(
            id: CanvasGenerationGroupID(uuid(20)),
            generatorID: generator.id,
            name: "金币成片",
            memberNodeIDs: [generatedNode.id],
            origin: WorldPoint(x: 0, y: 0),
            createdAt: date(20),
            updatedAt: date(20)
        )
        let workspace = Workspace(
            title: "Layers",
            assets: [source, generated],
            promptModules: [module],
            recipes: [recipe],
            generators: [generator],
            generationGroups: [group],
            canvasNodes: [
                generatorNode,
                sourceNode,
                recipeNode,
                generatedNode,
                moduleNode
            ]
        )

        let sections = WorkspaceLayerProjection.sections(in: workspace)

        XCTAssertEqual(
            sections.map(\.kind),
            [.sourceImages, .generatedImages, .promptModules, .recipes, .generators]
        )
        XCTAssertEqual(sections.map(\.count), [1, 1, 1, 1, 1])
        XCTAssertEqual(sections.flatMap(\.rows).count, workspace.canvasNodes.count)

        let sourceRow = sections[0].rows[0]
        XCTAssertEqual(sourceRow.nodeID, sourceNode.id)
        XCTAssertEqual(sourceRow.imageAssetID, source.id)
        XCTAssertEqual(sourceRow.entityID, source.id.rawValue)
        XCTAssertEqual(sourceRow.title, "客厅参考.jpg")
        XCTAssertEqual(sourceRow.secondaryDetail, "原图 · 1200 × 800")

        let generatedRow = sections[1].rows[0]
        XCTAssertEqual(generatedRow.nodeID, generatedNode.id)
        XCTAssertEqual(generatedRow.title, "金币成片 · 第 1 张")
        XCTAssertEqual(generatedRow.secondaryDetail, "生成结果 · 1024 × 1024")
        XCTAssertEqual(generatedRow.generationGroupID, group.id)
        XCTAssertEqual(generatedRow.generationGroupName, "金币成片")
        XCTAssertEqual(generatedRow.generationGroupOrdinal, 1)

        XCTAssertEqual(sections[2].rows[0].title, "主体")
        XCTAssertEqual(sections[2].rows[0].secondaryDetail, "一枚悬浮的金色纪念币")
        XCTAssertEqual(sections[3].rows[0].title, "金币海报组合")
        XCTAssertEqual(sections[3].rows[0].secondaryDetail, "1 个提示词模块")
        XCTAssertEqual(sections[4].rows[0].title, "金币海报")
        XCTAssertEqual(sections[4].rows[0].secondaryDetail, "1:1 · 1 个提示词模块")
    }

    func testCopiedImageOccurrencesRemainSeparateRowsAndSortByLayerOrder() {
        let sharedAsset = asset(id: 30, kind: .source, name: "参考图.png")
        let lower = imageNode(id: 31, assetID: sharedAsset.id, zIndex: 2, createdAt: 300)
        let upper = imageNode(id: 32, assetID: sharedAsset.id, zIndex: 9, createdAt: 100)
        let tiedNewer = imageNode(id: 33, assetID: sharedAsset.id, zIndex: 9, createdAt: 200)

        let forward = Workspace(
            title: "Forward",
            assets: [sharedAsset],
            canvasNodes: [lower, upper, tiedNewer]
        )
        let reversed = Workspace(
            title: "Reversed",
            assets: [sharedAsset],
            canvasNodes: [tiedNewer, upper, lower]
        )

        let forwardRows = WorkspaceLayerProjection.rows(in: forward)
        let reversedRows = WorkspaceLayerProjection.rows(in: reversed)

        XCTAssertEqual(forwardRows, reversedRows)
        XCTAssertEqual(forwardRows.map(\.nodeID), [tiedNewer.id, upper.id, lower.id])
        XCTAssertEqual(Set(forwardRows.map(\.nodeID)).count, 3)
        XCTAssertEqual(Set(forwardRows.compactMap(\.imageAssetID)), [sharedAsset.id])
    }

    func testGenerationGroupAddsMetadataWithoutCreatingAnExtraSection() {
        let firstAsset = asset(id: 40, kind: .generated, name: "generation-a.jpg")
        let secondAsset = asset(id: 41, kind: .generated, name: "generation-b.jpg")
        let firstNode = imageNode(id: 42, assetID: firstAsset.id, zIndex: 1)
        let secondNode = imageNode(id: 43, assetID: secondAsset.id, zIndex: 2)
        let group = CanvasGenerationGroup(
            id: CanvasGenerationGroupID(uuid(44)),
            generatorID: nil,
            name: "室内方案",
            memberNodeIDs: [firstNode.id, secondNode.id],
            origin: WorldPoint(x: 10, y: 20)
        )
        let workspace = Workspace(
            title: "Grouped",
            assets: [firstAsset, secondAsset],
            generationGroups: [group],
            canvasNodes: [firstNode, secondNode]
        )

        let sections = WorkspaceLayerProjection.sections(in: workspace)

        XCTAssertEqual(sections.map(\.kind), [.generatedImages])
        XCTAssertEqual(sections[0].rows.map(\.nodeID), [secondNode.id, firstNode.id])
        XCTAssertEqual(sections[0].rows.map(\.generationGroupOrdinal), [2, 1])
        XCTAssertEqual(
            sections[0].rows.map(\.title),
            ["室内方案 · 第 2 张", "室内方案 · 第 1 张"]
        )
    }

    func testMissingEntitiesRemainRepresentedAndEmptySectionsAreOptional() {
        let missingAssetID = AssetID(uuid(50))
        let missingRecipeID = RecipeID(uuid(51))
        let imageNode = imageNode(id: 52, assetID: missingAssetID, zIndex: 1)
        let recipeNode = CanvasNode(
            id: CanvasNodeID(uuid(53)),
            recipeID: missingRecipeID,
            frame: frame,
            zIndex: 2
        )
        let workspace = Workspace(
            title: "Dangling",
            canvasNodes: [imageNode, recipeNode]
        )

        let populated = WorkspaceLayerProjection.sections(in: workspace)
        XCTAssertEqual(populated.map(\.kind), [.sourceImages, .recipes])
        XCTAssertEqual(populated[0].rows[0].title, "缺失图片")
        XCTAssertEqual(populated[1].rows[0].title, "缺失提示词组合")
        XCTAssertEqual(populated.flatMap(\.rows).map(\.nodeID), [imageNode.id, recipeNode.id])

        let all = WorkspaceLayerProjection.sections(
            in: workspace,
            includeEmptySections: true
        )
        XCTAssertEqual(all.map(\.kind), WorkspaceLayerKind.allCases)
        XCTAssertEqual(all.map(\.count), [1, 0, 0, 0, 1, 0])
    }

    private var frame: WorldRect {
        WorldRect(x: 0, y: 0, width: 320, height: 240)
    }

    private func asset(
        id: Int,
        kind: AssetKind,
        name: String,
        width: Int? = nil,
        height: Int? = nil
    ) -> Asset {
        Asset(
            id: AssetID(uuid(id)),
            kind: kind,
            state: .ready,
            displayName: name,
            relativePath: "assets/\(name)",
            mimeType: "image/jpeg",
            pixelSize: width.flatMap { width in
                height.map { PixelSize(width: width, height: $0) }
            },
            createdAt: date(TimeInterval(id))
        )
    }

    private func imageNode(
        id: Int,
        assetID: AssetID,
        zIndex: Int,
        createdAt: TimeInterval? = nil
    ) -> CanvasNode {
        CanvasNode(
            id: CanvasNodeID(uuid(id)),
            imageAssetID: assetID,
            frame: frame,
            zIndex: zIndex,
            createdAt: date(createdAt ?? TimeInterval(id))
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
