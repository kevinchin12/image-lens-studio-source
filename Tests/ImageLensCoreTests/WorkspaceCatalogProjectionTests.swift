import Foundation
import XCTest
@testable import ImageLensCore

final class WorkspaceCatalogProjectionTests: XCTestCase {
    private let target = CompileTarget(
        providerID: "test",
        modelID: "image-model",
        languageCode: "zh-Hans"
    )

    func testLibraryUsesPersistedUserIntent() {
        let source = asset(id: 1, kind: .source)
        let unsavedGeneration = asset(id: 2, kind: .generated)
        let savedGeneration = asset(id: 3, kind: .generated, isSavedToLibrary: true)
        let removedSource = asset(id: 4, kind: .source, isSavedToLibrary: false)
        let assets = [unsavedGeneration, source, savedGeneration, removedSource]

        XCTAssertEqual(
            WorkspaceCatalogProjection.libraryAssets(from: assets).map(\.id),
            [source.id, savedGeneration.id]
        )
        XCTAssertFalse(WorkspaceCatalogProjection.isLibraryAsset(unsavedGeneration))
        XCTAssertTrue(WorkspaceCatalogProjection.isLibraryAsset(savedGeneration))
    }

    func testCustomGeneratorNameWinsAndIsCompacted() {
        let recipeID = RecipeID(uuid(10))
        let generator = Generator(
            name: "黑金浮雕金币产品主视觉特别版本",
            recipeID: recipeID,
            target: target
        )

        let title = GenerationHistoryTitlePolicy.baseTitle(
            generator: generator,
            compiledPrompt: compiledPrompt(
                id: 11,
                recipeID: recipeID,
                inputs: [(.subject, "一只透明玻璃杯")]
            ),
            recipe: recipe(id: recipeID, name: "备用配方")
        )

        XCTAssertEqual(title, "黑金浮雕金币产品主视觉特别版本")
        XCTAssertLessThanOrEqual(
            title.count,
            GenerationHistoryTitlePolicy.maximumBaseTitleLength
        )
    }

    func testDefaultGeneratorNameFallsBackToStructuredPromptInputs() {
        let recipeID = RecipeID(uuid(20))
        let generator = Generator(
            name: "生图 7",
            recipeID: recipeID,
            target: target
        )
        let snapshot = compiledPrompt(
            id: 21,
            recipeID: recipeID,
            inputs: [
                (.rendering, "干净的高分辨率渲染"),
                (.style, "黑金浮雕质感"),
                (.subject, "悬浮的椭圆形纪念金币")
            ]
        )

        XCTAssertEqual(
            GenerationHistoryTitlePolicy.baseTitle(
                generator: generator,
                compiledPrompt: snapshot,
                recipe: recipe(id: recipeID, name: "提示词组合 2")
            ),
            "悬浮椭圆形纪念金币 · 黑金浮雕"
        )
    }

    func testFinalTextAndRecipeAreUsedAsSuccessiveFallbacks() {
        let recipeID = RecipeID(uuid(30))
        let finalTextSnapshot = compiledPrompt(
            id: 31,
            recipeID: recipeID,
            finalText: "月光下的玻璃香水瓶，银蓝色摄影棚背景，柔和轮廓光"
        )

        XCTAssertEqual(
            GenerationHistoryTitlePolicy.baseTitle(
                generator: nil,
                compiledPrompt: finalTextSnapshot,
                recipe: recipe(id: recipeID, name: "香水产品图")
            ),
            "月光下玻璃香水瓶 · 银蓝色摄影棚"
        )
        XCTAssertEqual(
            GenerationHistoryTitlePolicy.baseTitle(
                generator: nil,
                compiledPrompt: nil,
                recipe: recipe(id: recipeID, name: "春季香水主视觉")
            ),
            "春季香水主视觉"
        )
        XCTAssertEqual(
            GenerationHistoryTitlePolicy.baseTitle(
                generator: nil,
                compiledPrompt: nil,
                recipe: recipe(id: recipeID, name: "提示词组合 3")
            ),
            "未命名图像创作"
        )
    }

    func testHistoryOrdinalsAreStableAcrossInputOrderAndUseTopicIdentity() {
        let recipeID = RecipeID(uuid(40))
        let generatorID = GeneratorID(uuid(41))
        let promptID = CompiledPromptID(uuid(42))
        let first = generation(
            id: 43,
            generatorID: generatorID,
            recipeID: recipeID,
            promptID: promptID,
            createdAt: 100
        )
        let second = generation(
            id: 44,
            generatorID: generatorID,
            recipeID: recipeID,
            promptID: promptID,
            createdAt: 200
        )
        let generator = Generator(
            id: generatorID,
            name: "浮雕金币",
            recipeID: recipeID,
            target: target
        )

        let forward = WorkspaceCatalogProjection.generationHistory(
            records: [first, second],
            generators: [generator],
            compiledPrompts: [],
            recipes: []
        )
        let reversed = WorkspaceCatalogProjection.generationHistory(
            records: [second, first],
            generators: [generator],
            compiledPrompts: [],
            recipes: []
        )

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.map(\.id), [second.id, first.id])
        XCTAssertEqual(forward.map(\.topicOrdinal), [2, 1])
        XCTAssertEqual(
            forward.map(\.displayTitle),
            ["浮雕金币 · 第 2 次", "浮雕金币 · 第 1 次"]
        )
    }

    func testDeletedGeneratorStillGroupsHistoryByPersistedGeneratorID() {
        let recipeID = RecipeID(uuid(50))
        let deletedGeneratorID = GeneratorID(uuid(51))
        let firstPrompt = compiledPrompt(
            id: 52,
            recipeID: recipeID,
            inputs: [(.subject, "金色纪念币")]
        )
        let secondPrompt = compiledPrompt(
            id: 53,
            recipeID: recipeID,
            inputs: [(.subject, "黑色背景上的金色纪念币")]
        )
        let first = generation(
            id: 54,
            generatorID: deletedGeneratorID,
            recipeID: recipeID,
            promptID: firstPrompt.id,
            createdAt: 100
        )
        let second = generation(
            id: 55,
            generatorID: deletedGeneratorID,
            recipeID: recipeID,
            promptID: secondPrompt.id,
            createdAt: 200
        )

        let items = WorkspaceCatalogProjection.generationHistory(
            records: [second, first],
            generators: [],
            compiledPrompts: [firstPrompt, secondPrompt],
            recipes: []
        )

        XCTAssertEqual(items.map(\.topicOrdinal), [2, 1])
        XCTAssertTrue(items[0].displayTitle.hasSuffix("第 2 次"))
        XCTAssertTrue(items[1].displayTitle.hasSuffix("第 1 次"))
    }

    func testHistoryHonorsFrozenDisplayTitleAndGeneratorNameSnapshot() {
        let recipeID = RecipeID(uuid(60))
        let generatorID = GeneratorID(uuid(61))
        let prompt = compiledPrompt(
            id: 62,
            recipeID: recipeID,
            inputs: [(.subject, "这段提示词不应覆盖冻结标题")]
        )
        let frozen = GenerationRecord(
            id: GenerationID(uuid(63)),
            generatorID: generatorID,
            recipeID: recipeID,
            promptSnapshotID: prompt.id,
            providerID: "test",
            modelID: "image-model",
            aspectRatio: "1:1",
            state: .succeeded,
            generatorNameSnapshot: "旧名称",
            displayTitle: "浮雕金币 · 第 3 次",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let item = WorkspaceCatalogProjection.generationHistory(
            records: [frozen],
            generators: [],
            compiledPrompts: [prompt],
            recipes: []
        )[0]

        XCTAssertEqual(item.baseTitle, "浮雕金币")
        XCTAssertEqual(item.displayTitle, "浮雕金币 · 第 3 次")
    }

    func testFrozenBaseTitleReceivesStableTopicOrdinal() {
        let recipeID = RecipeID(uuid(64))
        let generatorID = GeneratorID(uuid(65))
        let promptID = CompiledPromptID(uuid(66))
        let first = GenerationRecord(
            id: GenerationID(uuid(67)),
            generatorID: generatorID,
            recipeID: recipeID,
            promptSnapshotID: promptID,
            providerID: "test",
            modelID: "image-model",
            aspectRatio: "1:1",
            state: .succeeded,
            displayTitle: "浮雕金币",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let second = GenerationRecord(
            id: GenerationID(uuid(68)),
            generatorID: generatorID,
            recipeID: recipeID,
            promptSnapshotID: promptID,
            providerID: "test",
            modelID: "image-model",
            aspectRatio: "1:1",
            state: .succeeded,
            displayTitle: "浮雕金币",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let items = WorkspaceCatalogProjection.generationHistory(
            records: [first, second],
            generators: [],
            compiledPrompts: [],
            recipes: []
        )

        XCTAssertEqual(
            items.map(\.displayTitle),
            ["浮雕金币 · 第 2 次", "浮雕金币 · 第 1 次"]
        )
    }

    func testDefaultNameSnapshotDoesNotHideCurrentCustomGeneratorName() {
        let recipeID = RecipeID(uuid(70))
        let generatorID = GeneratorID(uuid(71))
        let promptID = CompiledPromptID(uuid(72))
        let record = GenerationRecord(
            id: GenerationID(uuid(73)),
            generatorID: generatorID,
            recipeID: recipeID,
            promptSnapshotID: promptID,
            providerID: "test",
            modelID: "image-model",
            aspectRatio: "1:1",
            state: .succeeded,
            generatorNameSnapshot: "生图 1",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let generator = Generator(
            id: generatorID,
            name: "香水产品主视觉",
            recipeID: recipeID,
            target: target
        )

        let item = WorkspaceCatalogProjection.generationHistory(
            records: [record],
            generators: [generator],
            compiledPrompts: [],
            recipes: []
        )[0]

        XCTAssertEqual(item.displayTitle, "香水产品主视觉")
    }

    private func asset(
        id: Int,
        kind: AssetKind,
        isSavedToLibrary: Bool? = nil
    ) -> Asset {
        Asset(
            id: AssetID(uuid(id)),
            kind: kind,
            isSavedToLibrary: isSavedToLibrary,
            displayName: "\(id).png",
            relativePath: "assets/\(id).png",
            mimeType: "image/png"
        )
    }

    private func recipe(id: RecipeID, name: String) -> Recipe {
        Recipe(id: id, name: name, target: target)
    }

    private func compiledPrompt(
        id: Int,
        recipeID: RecipeID,
        inputs: [(PromptModuleCategory, String)] = [],
        finalText: String = ""
    ) -> CompiledPromptSnapshot {
        CompiledPromptSnapshot(
            id: CompiledPromptID(uuid(id)),
            recipeID: recipeID,
            target: target,
            moduleInputs: inputs.enumerated().map { index, input in
                ModuleInputSnapshot(
                    moduleID: PromptModuleID(uuid(id * 100 + index + 1)),
                    revision: 0,
                    role: .visual(input.0),
                    resolvedContent: input.1,
                    evidence: .userProvided
                )
            },
            baseText: finalText,
            finalText: finalText,
            override: nil,
            sourceModuleIDs: [],
            warnings: []
        )
    }

    private func generation(
        id: Int,
        generatorID: GeneratorID?,
        recipeID: RecipeID,
        promptID: CompiledPromptID,
        createdAt: TimeInterval
    ) -> GenerationRecord {
        GenerationRecord(
            id: GenerationID(uuid(id)),
            generatorID: generatorID,
            recipeID: recipeID,
            promptSnapshotID: promptID,
            providerID: "test",
            modelID: "image-model",
            aspectRatio: "1:1",
            state: .succeeded,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    private func uuid(_ ordinal: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                ordinal
            )
        )!
    }
}
