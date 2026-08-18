import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class CanvasNodeCopyPayloadTests: XCTestCase {
    func testCopyingImageAndGeneratorRemapsPinnedReferenceToCopiedImage() throws {
        let asset = Asset(
            kind: .source,
            displayName: "reference.png",
            relativePath: "Assets/reference.png",
            mimeType: "image/png"
        )
        let sourceNode = CanvasNode(
            imageAssetID: asset.id,
            frame: WorldRect(x: 20, y: 40, width: 420, height: 320),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let target = CompileTarget(providerID: "gemini", modelID: "image-model")
        let recipe = Recipe(name: "Pinned recipe", target: target)
        let generator = Generator(
            name: "Pinned generator",
            recipeID: recipe.id,
            target: target,
            assetBindings: [
                GeneratorAssetBinding(
                    assetID: asset.id,
                    sourceCanvasNodeID: sourceNode.id,
                    role: .general,
                    order: 0
                )
            ]
        )
        let generatorNode = CanvasNode(
            generatorID: generator.id,
            frame: WorldRect(x: 600, y: 80, width: 440, height: 426)
        )
        var workspace = Workspace(
            title: "Pinned reference",
            assets: [asset],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [sourceNode, generatorNode]
        )

        let payload = try XCTUnwrap(
            CanvasNodeCopyPayload(
                workspace: workspace,
                selectedNodeIDs: [sourceNode.id, generatorNode.id]
            )
        )
        let result = payload.paste(into: &workspace, offset: WorldSize(width: 80, height: 0))

        XCTAssertEqual(workspace.generators.first?.assetBindings.first?.sourceCanvasNodeID, sourceNode.id)
        let pastedGenerator = try XCTUnwrap(result.generators.first)
        let pastedSourceNodeID = try XCTUnwrap(result.nodeIDMap[sourceNode.id])
        XCTAssertEqual(pastedGenerator.assetBindings.first?.sourceCanvasNodeID, pastedSourceNodeID)
    }

    func testImagePasteReusesAssetAndLeavesHeavyWorkspaceCollectionsUntouched() throws {
        let asset = Asset(
            kind: .source,
            state: .ready,
            displayName: "source.png",
            relativePath: "Assets/source.png",
            thumbnailRelativePath: "Thumbnails/source.png",
            mimeType: "image/png",
            pixelSize: PixelSize(width: 4096, height: 3072),
            contentHash: "same-image-bytes"
        )
        let snapshot = AnalysisSnapshot(
            assetID: asset.id,
            providerID: "gemini",
            modelID: "analysis-model",
            schemaVersion: "1",
            moduleIDs: []
        )
        let imageNode = CanvasNode(
            imageAssetID: asset.id,
            frame: WorldRect(x: 10, y: 20, width: 420, height: 320),
            zIndex: 2
        )
        var workspace = Workspace(
            title: "Copy",
            assets: [asset],
            analysisSnapshots: [snapshot],
            canvasNodes: [imageNode]
        )
        let originalAssets = workspace.assets
        let originalSnapshots = workspace.analysisSnapshots
        let originalCompiledPrompts = workspace.compiledPrompts
        let originalGenerations = workspace.generations
        let originalJobs = workspace.jobs

        let payload = try XCTUnwrap(
            CanvasNodeCopyPayload(workspace: workspace, selectedNodeIDs: [imageNode.id])
        )
        let result = payload.paste(
            into: &workspace,
            offset: WorldSize(width: 36, height: -12)
        )

        XCTAssertTrue(payload.promptModules.isEmpty)
        XCTAssertTrue(payload.recipes.isEmpty)
        XCTAssertTrue(payload.generators.isEmpty)
        XCTAssertEqual(workspace.assets, originalAssets)
        XCTAssertEqual(workspace.analysisSnapshots, originalSnapshots)
        XCTAssertEqual(workspace.compiledPrompts, originalCompiledPrompts)
        XCTAssertEqual(workspace.generations, originalGenerations)
        XCTAssertEqual(workspace.jobs, originalJobs)
        XCTAssertEqual(workspace.canvasNodes.count, 2)

        let pasted = try XCTUnwrap(result.nodes.first)
        XCTAssertNotEqual(pasted.id, imageNode.id)
        XCTAssertEqual(pasted.imageAssetID, asset.id)
        XCTAssertEqual(pasted.frame.origin, WorldPoint(x: 46, y: 8))
        XCTAssertEqual(pasted.frame.size, imageNode.frame.size)
    }

    func testGroupPasteClonesEntitiesAndRemapsInternalRecipeConnection() throws {
        let referenceAsset = Asset(
            kind: .source,
            displayName: "reference.png",
            relativePath: "Assets/reference.png",
            mimeType: "image/png"
        )
        let selectedModule = PromptModule(
            role: .visual(.style),
            content: "ceramic editorial",
            evidence: .userProvided
        )
        let externalModule = PromptModule(
            role: .visual(.lighting),
            content: "soft window light",
            evidence: .observable
        )
        let selectedBinding = RecipeInputBinding(
            moduleID: selectedModule.id,
            role: selectedModule.role,
            order: 0,
            priority: .primary
        )
        let externalBinding = RecipeInputBinding(
            moduleID: externalModule.id,
            role: externalModule.role,
            order: 1
        )
        let target = CompileTarget(providerID: "gemini", modelID: "image-model")
        let recipe = Recipe(
            name: "Editorial",
            bindings: [selectedBinding, externalBinding],
            target: target
        )
        let assetBinding = GeneratorAssetBinding(
            assetID: referenceAsset.id,
            role: .style,
            order: 0
        )
        let generator = Generator(
            name: "Render",
            recipeID: recipe.id,
            promptText: "A quiet ceramic editorial portrait",
            target: target,
            parameters: GenerationParameters(aspectRatio: "3:2", seed: 42),
            assetBindings: [assetBinding],
            mediaKind: .video,
            imageEdit: ImageEditConfiguration(
                sourceAssetID: referenceAsset.id,
                maskRelativePath: "assets/derived/mask.png",
                maskPixelSize: PixelSize(width: 1024, height: 1024),
                maskContentHash: "mask-hash"
            )
        )
        let moduleNode = CanvasNode(
            promptModuleID: selectedModule.id,
            frame: WorldRect(x: -100, y: 30, width: 280, height: 160),
            zIndex: 3
        )
        let recipeNode = CanvasNode(
            recipeID: recipe.id,
            frame: WorldRect(x: 240, y: 40, width: 300, height: 220),
            zIndex: 4
        )
        let generatorNode = CanvasNode(
            generatorID: generator.id,
            frame: WorldRect(x: 600, y: 100, width: 320, height: 260),
            zIndex: 5
        )
        var workspace = Workspace(
            title: "Graph",
            assets: [referenceAsset],
            promptModules: [selectedModule, externalModule],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [moduleNode, recipeNode, generatorNode]
        )

        let payload = try XCTUnwrap(
            CanvasNodeCopyPayload(
                workspace: workspace,
                selectedNodeIDs: [moduleNode.id, recipeNode.id, generatorNode.id]
            )
        )
        let result = payload.paste(
            into: &workspace,
            offset: WorldSize(width: 48, height: 64)
        )

        XCTAssertEqual(result.nodes.count, 3)
        XCTAssertEqual(result.promptModules.count, 1)
        XCTAssertEqual(result.recipes.count, 1, "shared recipe must be cloned only once")
        XCTAssertEqual(result.generators.count, 1)

        let pastedModule = try XCTUnwrap(result.promptModules.first)
        let pastedRecipe = try XCTUnwrap(result.recipes.first)
        let pastedGenerator = try XCTUnwrap(result.generators.first)
        XCTAssertNotEqual(pastedModule.id, selectedModule.id)
        XCTAssertNotEqual(pastedRecipe.id, recipe.id)
        XCTAssertNotEqual(pastedGenerator.id, generator.id)
        XCTAssertEqual(pastedGenerator.recipeID, pastedRecipe.id)
        XCTAssertEqual(pastedGenerator.target, target)
        XCTAssertEqual(pastedRecipe.target, target)
        XCTAssertEqual(pastedGenerator.parameters, generator.parameters)
        XCTAssertEqual(pastedGenerator.promptText, generator.promptText)
        XCTAssertEqual(pastedGenerator.mediaKind, .video)
        XCTAssertEqual(pastedGenerator.imageEdit, generator.imageEdit)
        XCTAssertEqual(pastedRecipe.name, "Editorial 副本")
        XCTAssertEqual(pastedGenerator.name, "Render 副本")

        let remappedBinding = try XCTUnwrap(
            pastedRecipe.bindings.first { $0.moduleID == pastedModule.id }
        )
        XCTAssertNotEqual(remappedBinding.id, selectedBinding.id)
        XCTAssertEqual(remappedBinding.role, selectedBinding.role)
        XCTAssertTrue(
            pastedRecipe.bindings.contains { $0.moduleID == externalModule.id },
            "recipe-owned references outside the copied node group remain valid"
        )
        let pastedAssetBinding = try XCTUnwrap(pastedGenerator.assetBindings.first)
        XCTAssertNotEqual(pastedAssetBinding.id, assetBinding.id)
        XCTAssertEqual(pastedAssetBinding.assetID, referenceAsset.id)

        let pastedRecipeNode = try XCTUnwrap(result.nodes.first { $0.kind == .recipe })
        let pastedGeneratorNode = try XCTUnwrap(result.nodes.first { $0.kind == .generation })
        XCTAssertEqual(pastedRecipeNode.recipeID, pastedRecipe.id)
        XCTAssertEqual(pastedGeneratorNode.generatorID, pastedGenerator.id)
        XCTAssertEqual(pastedGeneratorNode.frame.height, 426)

        let pastedModuleNode = try XCTUnwrap(result.nodes.first { $0.kind == .module })
        XCTAssertEqual(pastedModuleNode.promptModuleID, pastedModule.id)
        XCTAssertEqual(
            pastedGeneratorNode.frame.origin.x - pastedModuleNode.frame.origin.x,
            generatorNode.frame.origin.x - moduleNode.frame.origin.x
        )
        XCTAssertEqual(
            pastedGeneratorNode.frame.origin.y - pastedModuleNode.frame.origin.y,
            generatorNode.frame.origin.y - moduleNode.frame.origin.y
        )
        XCTAssertTrue(result.nodes.allSatisfy { $0.zIndex > generatorNode.zIndex })
    }

    func testRepeatedPasteCreatesFreshIDsAndGeneratorOnlyKeepsRecipeInputs() throws {
        let module = PromptModule(
            role: .instruction,
            content: "make it quieter",
            evidence: .userProvided
        )
        let target = CompileTarget(providerID: "gemini", modelID: "image-model")
        let recipe = Recipe(
            name: "提示词组合 1",
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
        let generator = Generator(name: "生图 1", recipeID: recipe.id, target: target)
        let generatorNode = CanvasNode(
            generatorID: generator.id,
            frame: WorldRect(x: 0, y: 0, width: 320, height: 260)
        )
        var workspace = Workspace(
            title: "Repeat",
            promptModules: [module],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [generatorNode]
        )
        let payload = try XCTUnwrap(
            CanvasNodeCopyPayload(workspace: workspace, selectedNodeIDs: [generatorNode.id])
        )

        let first = payload.paste(into: &workspace, offset: .zero)
        let second = payload.paste(
            into: &workspace,
            offset: WorldSize(width: 32, height: 32)
        )

        XCTAssertTrue(first.promptModules.isEmpty)
        XCTAssertTrue(second.promptModules.isEmpty)
        XCTAssertNotEqual(first.nodes.first?.id, second.nodes.first?.id)
        XCTAssertNotEqual(first.generators.first?.id, second.generators.first?.id)
        XCTAssertNotEqual(first.recipes.first?.id, second.recipes.first?.id)
        XCTAssertEqual(first.recipes.first?.bindings.first?.moduleID, module.id)
        XCTAssertEqual(second.recipes.first?.bindings.first?.moduleID, module.id)
        XCTAssertEqual(first.recipes.first?.name, "提示词组合 2")
        XCTAssertEqual(second.recipes.first?.name, "提示词组合 3")
        XCTAssertEqual(first.generators.first?.name, "生图 2")
        XCTAssertEqual(second.generators.first?.name, "生图 3")
        XCTAssertEqual(first.nodes.first?.frame.height, 426)
        XCTAssertEqual(second.nodes.first?.frame.height, 426)
    }

    func testGeneratedResultGroupPasteReusesAssetsAndClonesOnlyPresentationMetadata() throws {
        let generatorID = GeneratorID()
        let firstAsset = Asset(
            kind: .generated,
            displayName: "result-1.png",
            relativePath: "Derived/result-1.png",
            mimeType: "image/png"
        )
        let secondAsset = Asset(
            kind: .generated,
            displayName: "result-2.png",
            relativePath: "Derived/result-2.png",
            mimeType: "image/png"
        )
        let firstNode = CanvasNode(
            imageAssetID: firstAsset.id,
            frame: WorldRect(x: 124, y: 180, width: 320, height: 320),
            zIndex: 8
        )
        let secondNode = CanvasNode(
            imageAssetID: secondAsset.id,
            frame: WorldRect(x: 476, y: 180, width: 320, height: 180),
            zIndex: 9
        )
        let group = CanvasGenerationGroup(
            generatorID: generatorID,
            name: "生成结果 1",
            memberNodeIDs: [firstNode.id, secondNode.id],
            origin: WorldPoint(x: 100, y: 96),
            isCollapsed: true
        )
        var workspace = Workspace(
            title: "Grouped results",
            assets: [firstAsset, secondAsset],
            generationGroups: [group],
            canvasNodes: [firstNode, secondNode]
        )

        let payload = try XCTUnwrap(
            CanvasNodeCopyPayload(
                workspace: workspace,
                selectedNodeIDs: [firstNode.id, secondNode.id]
            )
        )
        let originalAssets = workspace.assets
        let result = payload.paste(
            into: &workspace,
            offset: WorldSize(width: 40, height: 56)
        )

        XCTAssertEqual(workspace.assets, originalAssets)
        XCTAssertEqual(workspace.canvasNodes.count, 4)
        XCTAssertEqual(workspace.generationGroups.count, 2)
        XCTAssertEqual(result.generationGroups.count, 1)
        let pastedGroup = try XCTUnwrap(result.generationGroups.first)
        XCTAssertNotEqual(pastedGroup.id, group.id)
        XCTAssertEqual(pastedGroup.generatorID, generatorID)
        XCTAssertEqual(pastedGroup.name, "生成结果 2")
        XCTAssertEqual(pastedGroup.origin, WorldPoint(x: 140, y: 152))
        XCTAssertTrue(pastedGroup.isCollapsed)
        XCTAssertEqual(
            pastedGroup.memberNodeIDs,
            group.memberNodeIDs.compactMap { result.nodeIDMap[$0] }
        )
        XCTAssertEqual(
            Set(result.nodes.compactMap(\.imageAssetID)),
            [firstAsset.id, secondAsset.id]
        )
    }

    func testNotePasteCreatesIndependentTextWithoutPromptData() throws {
        let note = TextBlock(text: "Keep the quiet version")
        let node = CanvasNode(
            textBlockID: note.id,
            frame: WorldRect(x: 40, y: 60, width: 280, height: 180)
        )
        var workspace = Workspace(
            title: "Notes",
            textBlocks: [note],
            canvasNodes: [node]
        )
        let payload = try XCTUnwrap(
            CanvasNodeCopyPayload(workspace: workspace, selectedNodeIDs: [node.id])
        )

        let result = payload.paste(
            into: &workspace,
            offset: WorldSize(width: 32, height: 32)
        )

        XCTAssertEqual(result.textBlocks.count, 1)
        XCTAssertNotEqual(result.textBlocks[0].id, note.id)
        XCTAssertEqual(result.textBlocks[0].text, note.text)
        XCTAssertEqual(result.nodes.first?.textBlockID, result.textBlocks[0].id)
        XCTAssertTrue(workspace.promptModules.isEmpty)
        XCTAssertTrue(workspace.recipes.isEmpty)
    }
}
