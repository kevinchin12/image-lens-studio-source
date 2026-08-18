import XCTest
@testable import ImageLensCore

final class WorkspaceStorageCleanupPolicyTests: XCTestCase {
    func testHistoryOnlyGeneratedAssetsAreRemovable() {
        let asset = generatedAsset()
        let generation = generation(outputAssetIDs: [asset.id])
        let workspace = Workspace(title: "Cleanup", assets: [asset], generations: [generation])

        XCTAssertEqual(
            WorkspaceStorageCleanupPolicy.removableGeneratedAssetIDs(in: workspace),
            [asset.id]
        )

        let cleaned = WorkspaceStorageCleanupPolicy.removingGeneratedAssets(
            [asset.id],
            from: workspace
        )
        XCTAssertTrue(cleaned.assets.isEmpty)
        XCTAssertTrue(cleaned.generations[0].outputAssetIDs.isEmpty)
        XCTAssertEqual(cleaned.generations[0].id, generation.id)
    }

    func testStrongReferencesKeepGeneratedAssets() {
        let assets = (0..<7).map { generatedAsset(index: $0) }
        let target = CompileTarget(providerID: "gemini", modelID: "image-model")
        let module = PromptModule(
            role: .instruction,
            content: "Prompt",
            sourceAssetID: assets[2].id,
            evidence: .userProvided
        )
        let snapshot = AnalysisSnapshot(
            assetID: assets[3].id,
            providerID: ProviderID("gemini"),
            modelID: "analysis",
            schemaVersion: "1",
            moduleIDs: []
        )
        let compiled = CompiledPromptSnapshot(
            recipeID: RecipeID(),
            target: target,
            moduleInputs: [
                ModuleInputSnapshot(
                    moduleID: PromptModuleID(),
                    revision: 0,
                    role: .instruction,
                    resolvedContent: "Prompt",
                    evidence: .userProvided,
                    sourceAssetID: assets[4].id
                )
            ],
            baseText: "Prompt",
            finalText: "Prompt",
            override: nil,
            sourceModuleIDs: [],
            warnings: []
        )
        let recipe = Recipe(name: "Recipe", target: target)
        let generator = Generator(
            name: "Generator",
            recipeID: recipe.id,
            target: target,
            assetBindings: [
                GeneratorAssetBinding(assetID: assets[1].id, role: .general, order: 0)
            ]
        )
        var material = assets[5]
        material.addUsage(.material)
        var archived = assets[6]
        archived.addUsage(.archived)
        var workspace = Workspace(
            title: "Cleanup",
            assets: [assets[0], assets[1], assets[2], assets[3], assets[4], material, archived],
            analysisSnapshots: [snapshot],
            promptModules: [module],
            recipes: [recipe],
            generators: [generator],
            compiledPrompts: [compiled],
            canvasNodes: [
                CanvasNode(
                    imageAssetID: assets[0].id,
                    frame: WorldRect(x: 0, y: 0, width: 100, height: 100)
                )
            ]
        )
        workspace.jobs = [
            JobRecord(kind: .analysis, state: .failed, subjectID: assets[3].id.rawValue)
        ]

        XCTAssertTrue(
            WorkspaceStorageCleanupPolicy.removableGeneratedAssetIDs(in: workspace).isEmpty
        )
    }

    func testSourceAliasIsNeverRemovedAndKeepsSharedFileAliveAtPolicyLevel() {
        let generated = generatedAsset()
        let alias = generated.sourceMaterialAlias()
        let workspace = Workspace(title: "Cleanup", assets: [generated, alias])

        XCTAssertEqual(
            WorkspaceStorageCleanupPolicy.removableGeneratedAssetIDs(in: workspace),
            [generated.id]
        )
        let cleaned = WorkspaceStorageCleanupPolicy.removingGeneratedAssets(
            [generated.id],
            from: workspace
        )
        XCTAssertEqual(cleaned.assets.map(\.id), [alias.id])
        XCTAssertEqual(cleaned.assets[0].relativePath, generated.relativePath)
    }

    func testImageEditSourceIsAStrongReference() {
        let source = generatedAsset()
        let recipe = Recipe(
            name: "Edit",
            target: CompileTarget(providerID: "gemini", modelID: "image-model")
        )
        let generator = Generator(
            name: "Edit",
            recipeID: recipe.id,
            target: recipe.target,
            imageEdit: ImageEditConfiguration(
                sourceAssetID: source.id,
                maskRelativePath: "assets/derived/mask.png",
                maskPixelSize: PixelSize(width: 1024, height: 1024)
            )
        )
        let run = GenerationRecord(
            generatorID: generator.id,
            recipeID: recipe.id,
            promptSnapshotID: CompiledPromptID(),
            providerID: "gemini",
            modelID: "image-model",
            aspectRatio: "1:1",
            imageEditSnapshot: ImageEditSnapshot(
                sourceAssetID: source.id,
                maskRelativePath: "assets/derived/mask.png",
                maskPixelSize: PixelSize(width: 1024, height: 1024)
            )
        )
        let workspace = Workspace(
            title: "Edit",
            assets: [source],
            recipes: [recipe],
            generators: [generator],
            generations: [run]
        )

        XCTAssertTrue(
            WorkspaceStorageCleanupPolicy.removableGeneratedAssetIDs(in: workspace).isEmpty
        )
    }

    private func generatedAsset(index: Int = 0) -> Asset {
        Asset(
            kind: .generated,
            state: .ready,
            displayName: "Result \(index)",
            relativePath: "assets/derived/result-\(index).png",
            mimeType: "image/png"
        )
    }

    private func generation(outputAssetIDs: [AssetID]) -> GenerationRecord {
        GenerationRecord(
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: ProviderID("gemini"),
            modelID: "model",
            aspectRatio: "16:9",
            state: .succeeded,
            outputAssetIDs: outputAssetIDs
        )
    }
}
