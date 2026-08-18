import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class CanvasNodeRemovalPolicyTests: XCTestCase {
    func testRemovingFinalGeneratorOccurrenceRemovesConfigurationAndUnreferencedRecipe() {
        let fixture = makeGenerator(name: "Disposable")
        let node = generatorNode(fixture.generator)
        let changedAt = Date(timeIntervalSince1970: 123)
        var workspace = Workspace(
            title: "Removal",
            recipes: [fixture.recipe],
            generators: [fixture.generator],
            canvasNodes: [node]
        )

        let result = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [node.id],
            from: &workspace,
            changedAt: changedAt
        )

        XCTAssertEqual(result.removedCanvasNodeIDs, [node.id])
        XCTAssertEqual(result.removedGeneratorIDs, [fixture.generator.id])
        XCTAssertEqual(result.removedRecipeIDs, [fixture.recipe.id])
        XCTAssertTrue(workspace.canvasNodes.isEmpty)
        XCTAssertTrue(workspace.generators.isEmpty)
        XCTAssertTrue(workspace.recipes.isEmpty)
        XCTAssertEqual(workspace.updatedAt, changedAt)
    }

    func testGeneratorConfigurationSurvivesUntilItsLastOccurrenceIsRemoved() {
        let fixture = makeGenerator(name: "Repeated")
        let firstNode = generatorNode(fixture.generator, x: 0)
        let secondNode = generatorNode(fixture.generator, x: 400)
        var workspace = Workspace(
            title: "Occurrences",
            recipes: [fixture.recipe],
            generators: [fixture.generator],
            canvasNodes: [firstNode, secondNode]
        )

        let firstResult = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [firstNode.id],
            from: &workspace
        )

        XCTAssertEqual(firstResult.removedCanvasNodeIDs, [firstNode.id])
        XCTAssertTrue(firstResult.removedGeneratorIDs.isEmpty)
        XCTAssertTrue(firstResult.removedRecipeIDs.isEmpty)
        XCTAssertEqual(workspace.canvasNodes, [secondNode])
        XCTAssertEqual(workspace.generators, [fixture.generator])
        XCTAssertEqual(workspace.recipes, [fixture.recipe])

        let secondResult = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [secondNode.id],
            from: &workspace
        )

        XCTAssertEqual(secondResult.removedGeneratorIDs, [fixture.generator.id])
        XCTAssertEqual(secondResult.removedRecipeIDs, [fixture.recipe.id])
        XCTAssertTrue(workspace.generators.isEmpty)
        XCTAssertTrue(workspace.recipes.isEmpty)
    }

    func testRemovingFinalGeneratorOccurrenceDetachesButPreservesGenerationGroup() {
        let fixture = makeGenerator(name: "Grouped")
        let generatorNode = generatorNode(fixture.generator)
        let resultAsset = Asset(
            kind: .generated,
            displayName: "result.png",
            relativePath: "assets/derived/result.png",
            mimeType: "image/png"
        )
        let memberNode = CanvasNode(
            imageAssetID: resultAsset.id,
            frame: WorldRect(x: 400, y: 0, width: 320, height: 320)
        )
        let changedAt = Date(timeIntervalSince1970: 234)
        let group = CanvasGenerationGroup(
            generatorID: fixture.generator.id,
            memberNodeIDs: [memberNode.id],
            origin: WorldPoint(x: 380, y: -60)
        )
        var workspace = Workspace(
            title: "Group detach",
            assets: [resultAsset],
            recipes: [fixture.recipe],
            generators: [fixture.generator],
            generationGroups: [group],
            canvasNodes: [generatorNode, memberNode]
        )

        let result = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [generatorNode.id],
            from: &workspace,
            changedAt: changedAt
        )

        XCTAssertEqual(result.removedGeneratorIDs, [fixture.generator.id])
        XCTAssertEqual(workspace.generationGroups.count, 1)
        XCTAssertNil(workspace.generationGroups[0].generatorID)
        XCTAssertEqual(workspace.generationGroups[0].memberNodeIDs, [memberNode.id])
        XCTAssertEqual(workspace.generationGroups[0].updatedAt, changedAt)
        XCTAssertEqual(workspace.canvasNodes, [memberNode])
    }

    func testHistoricalGenerationAndCompiledSnapshotKeepRecipesAfterGeneratorRemoval() {
        let generationFixture = makeGenerator(name: "Recorded")
        let snapshotFixture = makeGenerator(name: "Compiled")
        let generationNode = generatorNode(generationFixture.generator, x: 0)
        let snapshotNode = generatorNode(snapshotFixture.generator, x: 400)
        let promptSnapshotID = CompiledPromptID()
        let generation = GenerationRecord(
            generatorID: generationFixture.generator.id,
            recipeID: generationFixture.recipe.id,
            promptSnapshotID: promptSnapshotID,
            providerID: "test",
            modelID: "model",
            aspectRatio: "1:1",
            state: .succeeded
        )
        let compiledPrompt = CompiledPromptSnapshot(
            recipeID: snapshotFixture.recipe.id,
            target: snapshotFixture.recipe.target,
            baseText: "frozen prompt",
            finalText: "frozen prompt",
            override: nil,
            sourceModuleIDs: [],
            warnings: []
        )
        var workspace = Workspace(
            title: "History",
            recipes: [generationFixture.recipe, snapshotFixture.recipe],
            generators: [generationFixture.generator, snapshotFixture.generator],
            compiledPrompts: [compiledPrompt],
            generations: [generation],
            canvasNodes: [generationNode, snapshotNode]
        )
        let originalGenerations = workspace.generations
        let originalCompiledPrompts = workspace.compiledPrompts

        let result = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [generationNode.id, snapshotNode.id],
            from: &workspace
        )

        XCTAssertEqual(
            result.removedGeneratorIDs,
            [generationFixture.generator.id, snapshotFixture.generator.id]
        )
        XCTAssertTrue(result.removedRecipeIDs.isEmpty)
        XCTAssertEqual(
            Set(workspace.recipes.map(\.id)),
            [generationFixture.recipe.id, snapshotFixture.recipe.id]
        )
        XCTAssertEqual(workspace.generations, originalGenerations)
        XCTAssertEqual(workspace.compiledPrompts, originalCompiledPrompts)
    }

    func testDeletingFinalSourceLessModuleOccurrenceRemovesModuleAndEveryLiveBinding() {
        let changedAt = Date(timeIntervalSince1970: 321)
        let manualModule = PromptModule(
            role: .instruction,
            content: "temporary direction",
            evidence: .userProvided
        )
        let siblingModule = PromptModule(
            role: .instruction,
            content: "keep sibling",
            sourceAssetID: AssetID(),
            evidence: .observable
        )
        let firstRecipe = Recipe(
            name: "First",
            bindings: [
                RecipeInputBinding(
                    moduleID: manualModule.id,
                    role: manualModule.role,
                    order: 0
                ),
                RecipeInputBinding(
                    moduleID: siblingModule.id,
                    role: siblingModule.role,
                    order: 1
                ),
                RecipeInputBinding(
                    moduleID: manualModule.id,
                    role: manualModule.role,
                    order: 2
                )
            ],
            target: target,
            revision: 4
        )
        let secondRecipe = Recipe(
            name: "Second",
            bindings: [
                RecipeInputBinding(
                    moduleID: manualModule.id,
                    role: manualModule.role,
                    order: 0
                )
            ],
            target: target,
            revision: 8
        )
        let frozenSnapshot = CompiledPromptSnapshot(
            recipeID: firstRecipe.id,
            target: target,
            moduleInputs: [
                ModuleInputSnapshot(
                    moduleID: manualModule.id,
                    revision: 0,
                    role: manualModule.role,
                    resolvedContent: manualModule.content,
                    evidence: manualModule.evidence
                )
            ],
            baseText: manualModule.content,
            finalText: manualModule.content,
            override: nil,
            sourceModuleIDs: [manualModule.id],
            warnings: []
        )
        let node = CanvasNode(
            promptModuleID: manualModule.id,
            frame: WorldRect(x: 0, y: 0, width: 280, height: 160)
        )
        let firstRecipeNode = CanvasNode(
            recipeID: firstRecipe.id,
            frame: WorldRect(x: 320, y: 0, width: 320, height: 240)
        )
        let secondRecipeNode = CanvasNode(
            recipeID: secondRecipe.id,
            frame: WorldRect(x: 680, y: 0, width: 320, height: 240)
        )
        var workspace = Workspace(
            title: "Manual cleanup",
            promptModules: [manualModule, siblingModule],
            recipes: [firstRecipe, secondRecipe],
            compiledPrompts: [frozenSnapshot],
            canvasNodes: [node, firstRecipeNode, secondRecipeNode]
        )
        let originalSnapshots = workspace.compiledPrompts

        let result = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [node.id],
            from: &workspace,
            changedAt: changedAt
        )

        XCTAssertEqual(result.removedPromptModuleIDs, [manualModule.id])
        XCTAssertEqual(workspace.promptModules, [siblingModule])
        XCTAssertEqual(
            workspace.recipes[0].bindings.map(\.moduleID),
            [siblingModule.id]
        )
        XCTAssertTrue(workspace.recipes[1].bindings.isEmpty)
        XCTAssertEqual(workspace.recipes.map(\.revision), [5, 9])
        XCTAssertEqual(workspace.recipes.map(\.updatedAt), [changedAt, changedAt])
        XCTAssertEqual(workspace.compiledPrompts, originalSnapshots)
    }

    func testSourceLessModuleSurvivesUntilItsLastOccurrenceIsRemoved() {
        let module = PromptModule(
            role: .instruction,
            content: "shared occurrence",
            evidence: .userProvided
        )
        let binding = RecipeInputBinding(
            moduleID: module.id,
            role: module.role,
            order: 0
        )
        let recipe = Recipe(
            name: "Occurrences",
            bindings: [binding],
            target: target,
            revision: 2
        )
        let firstNode = CanvasNode(
            promptModuleID: module.id,
            frame: WorldRect(x: 0, y: 0, width: 280, height: 160)
        )
        let secondNode = CanvasNode(
            promptModuleID: module.id,
            frame: WorldRect(x: 320, y: 0, width: 280, height: 160)
        )
        let recipeNode = CanvasNode(
            recipeID: recipe.id,
            frame: WorldRect(x: 640, y: 0, width: 320, height: 240)
        )
        var workspace = Workspace(
            title: "Occurrences",
            promptModules: [module],
            recipes: [recipe],
            canvasNodes: [firstNode, secondNode, recipeNode]
        )

        let firstResult = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [firstNode.id],
            from: &workspace
        )

        XCTAssertTrue(firstResult.removedPromptModuleIDs.isEmpty)
        XCTAssertEqual(workspace.promptModules, [module])
        XCTAssertEqual(workspace.recipes, [recipe])

        let secondResult = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [secondNode.id],
            from: &workspace
        )

        XCTAssertEqual(secondResult.removedPromptModuleIDs, [module.id])
        XCTAssertTrue(workspace.promptModules.isEmpty)
        XCTAssertTrue(workspace.recipes[0].bindings.isEmpty)
        XCTAssertEqual(workspace.recipes[0].revision, 3)
    }

    func testRemovingFinalSourceLessModuleOccurrenceRemovesNewlyUnreferencedRecipe() {
        let module = PromptModule(
            role: .instruction,
            content: "disposable recipe",
            evidence: .userProvided
        )
        let recipe = Recipe(
            name: "Disposable",
            bindings: [
                RecipeInputBinding(
                    moduleID: module.id,
                    role: module.role,
                    order: 0
                )
            ],
            target: target
        )
        let node = CanvasNode(
            promptModuleID: module.id,
            frame: WorldRect(x: 0, y: 0, width: 280, height: 160)
        )
        var workspace = Workspace(
            title: "Recipe cleanup",
            promptModules: [module],
            recipes: [recipe],
            canvasNodes: [node]
        )

        let result = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [node.id],
            from: &workspace
        )

        XCTAssertEqual(result.removedPromptModuleIDs, [module.id])
        XCTAssertEqual(result.removedRecipeIDs, [recipe.id])
        XCTAssertTrue(workspace.promptModules.isEmpty)
        XCTAssertTrue(workspace.recipes.isEmpty)
    }

    func testMixedRemovalPreservesSourceDerivedModulesAndAssets() {
        let asset = Asset(
            kind: .source,
            displayName: "source.png",
            relativePath: "assets/source.png",
            mimeType: "image/png"
        )
        let module = PromptModule(
            role: .instruction,
            content: "keep this reusable",
            sourceAssetID: asset.id,
            evidence: .observable
        )
        let fixture = makeGenerator(name: "Mixed")
        let imageNode = CanvasNode(
            imageAssetID: asset.id,
            frame: WorldRect(x: 0, y: 0, width: 320, height: 240)
        )
        let moduleNode = CanvasNode(
            promptModuleID: module.id,
            frame: WorldRect(x: 360, y: 0, width: 280, height: 160)
        )
        let generationNode = generatorNode(fixture.generator, x: 680)
        var workspace = Workspace(
            title: "Mixed",
            assets: [asset],
            promptModules: [module],
            recipes: [fixture.recipe],
            generators: [fixture.generator],
            canvasNodes: [imageNode, moduleNode, generationNode]
        )
        let originalAssets = workspace.assets
        let originalModules = workspace.promptModules
        let originalGenerations = workspace.generations
        let originalCompiledPrompts = workspace.compiledPrompts

        let result = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [imageNode.id, moduleNode.id, generationNode.id],
            from: &workspace
        )

        XCTAssertEqual(
            result.removedCanvasNodeIDs,
            [imageNode.id, moduleNode.id, generationNode.id]
        )
        XCTAssertEqual(result.removedGeneratorIDs, [fixture.generator.id])
        XCTAssertEqual(result.removedRecipeIDs, [fixture.recipe.id])
        XCTAssertEqual(workspace.assets, originalAssets)
        XCTAssertEqual(workspace.promptModules, originalModules)
        XCTAssertEqual(workspace.generations, originalGenerations)
        XCTAssertEqual(workspace.compiledPrompts, originalCompiledPrompts)
    }

    func testRecipeCanvasOccurrenceKeepsRecipeAfterFinalGeneratorOccurrenceIsRemoved() {
        let fixture = makeGenerator(name: "Visible Recipe")
        let generatorNode = generatorNode(fixture.generator)
        let recipeNode = CanvasNode(
            recipeID: fixture.recipe.id,
            frame: WorldRect(x: 400, y: 0, width: 320, height: 240)
        )
        var workspace = Workspace(
            title: "Recipe root",
            recipes: [fixture.recipe],
            generators: [fixture.generator],
            canvasNodes: [generatorNode, recipeNode]
        )

        let result = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [generatorNode.id],
            from: &workspace
        )

        XCTAssertEqual(result.removedGeneratorIDs, [fixture.generator.id])
        XCTAssertTrue(result.removedRecipeIDs.isEmpty)
        XCTAssertEqual(workspace.recipes, [fixture.recipe])
        XCTAssertEqual(workspace.canvasNodes, [recipeNode])
    }

    func testPruneOrphanedGeneratorsIsIdempotentAndPreservesHistoricalRecipe() {
        let live = makeGenerator(name: "Live")
        let disposable = makeGenerator(name: "Orphan")
        let historical = makeGenerator(name: "Historical")
        let liveNode = generatorNode(live.generator)
        let generation = GenerationRecord(
            generatorID: historical.generator.id,
            recipeID: historical.recipe.id,
            promptSnapshotID: CompiledPromptID(),
            providerID: "test",
            modelID: "model",
            aspectRatio: "9:16",
            state: .succeeded
        )
        let firstChange = Date(timeIntervalSince1970: 456)
        var workspace = Workspace(
            title: "Migration",
            recipes: [live.recipe, disposable.recipe, historical.recipe],
            generators: [live.generator, disposable.generator, historical.generator],
            generations: [generation],
            canvasNodes: [liveNode]
        )

        let first = CanvasNodeRemovalPolicy.pruneOrphanedGenerators(
            in: &workspace,
            changedAt: firstChange
        )

        XCTAssertTrue(first.removedCanvasNodeIDs.isEmpty)
        XCTAssertEqual(
            first.removedGeneratorIDs,
            [disposable.generator.id, historical.generator.id]
        )
        XCTAssertEqual(first.removedRecipeIDs, [disposable.recipe.id])
        XCTAssertEqual(workspace.generators, [live.generator])
        XCTAssertEqual(
            Set(workspace.recipes.map(\.id)),
            [live.recipe.id, historical.recipe.id]
        )
        XCTAssertEqual(workspace.generations, [generation])
        XCTAssertEqual(workspace.updatedAt, firstChange)

        let normalizedWorkspace = workspace
        let second = CanvasNodeRemovalPolicy.pruneOrphanedGenerators(
            in: &workspace,
            changedAt: Date(timeIntervalSince1970: 999)
        )

        XCTAssertEqual(second, .empty)
        XCTAssertEqual(workspace, normalizedWorkspace)
    }

    func testPruneOrphanedGeneratorDetachesItsGenerationGroup() {
        let fixture = makeGenerator(name: "Orphaned Group")
        let memberNode = CanvasNode(
            imageAssetID: AssetID(),
            frame: WorldRect(x: 0, y: 0, width: 320, height: 320)
        )
        let group = CanvasGenerationGroup(
            generatorID: fixture.generator.id,
            memberNodeIDs: [memberNode.id],
            origin: .zero
        )
        let changedAt = Date(timeIntervalSince1970: 567)
        var workspace = Workspace(
            title: "Prune group",
            recipes: [fixture.recipe],
            generators: [fixture.generator],
            generationGroups: [group],
            canvasNodes: [memberNode]
        )

        let result = CanvasNodeRemovalPolicy.pruneOrphanedGenerators(
            in: &workspace,
            changedAt: changedAt
        )

        XCTAssertEqual(result.removedGeneratorIDs, [fixture.generator.id])
        XCTAssertNil(workspace.generationGroups[0].generatorID)
        XCTAssertEqual(workspace.generationGroups[0].updatedAt, changedAt)
        XCTAssertEqual(workspace.generationGroups[0].memberNodeIDs, [memberNode.id])
    }

    func testRetiringLegacyResultGroupsKeepsHistoryAssetsAndIndependentOccurrences() {
        let generationID = GenerationID()
        let groupedAsset = Asset(
            kind: .generated,
            displayName: "grouped.png",
            relativePath: "assets/derived/grouped.png",
            mimeType: "image/png",
            sourceGenerationID: generationID
        )
        let independentAsset = Asset(
            kind: .generated,
            displayName: "independent.png",
            relativePath: "assets/derived/independent.png",
            mimeType: "image/png",
            sourceGenerationID: generationID
        )
        let groupedNode = CanvasNode(
            imageAssetID: groupedAsset.id,
            frame: WorldRect(x: 0, y: 0, width: 320, height: 180)
        )
        let independentNode = CanvasNode(
            imageAssetID: independentAsset.id,
            frame: WorldRect(x: 400, y: 0, width: 320, height: 180)
        )
        let group = CanvasGenerationGroup(
            generatorID: nil,
            memberNodeIDs: [groupedNode.id],
            origin: .zero
        )
        let generation = GenerationRecord(
            id: generationID,
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: "gemini",
            modelID: "image-model",
            aspectRatio: "16:9",
            state: .succeeded,
            outputAssetIDs: [groupedAsset.id, independentAsset.id]
        )
        var workspace = Workspace(
            title: "Legacy groups",
            assets: [groupedAsset, independentAsset],
            generations: [generation],
            generationGroups: [group],
            canvasNodes: [groupedNode, independentNode]
        )

        XCTAssertTrue(CanvasNodeRemovalPolicy.retireLegacyGenerationResultGroups(in: &workspace))
        XCTAssertTrue(workspace.generationGroups.isEmpty)
        XCTAssertEqual(workspace.canvasNodes, [independentNode])
        XCTAssertEqual(workspace.assets, [groupedAsset, independentAsset])
        XCTAssertEqual(workspace.generations, [generation])
        XCTAssertFalse(CanvasNodeRemovalPolicy.retireLegacyGenerationResultGroups(in: &workspace))
    }

    func testPruneOrphanedSourceLessPromptModulesIsSelectiveAndIdempotent() {
        let orphan = PromptModule(
            role: .instruction,
            content: "orphan",
            evidence: .userProvided
        )
        let occurrenceRoot = PromptModule(
            role: .instruction,
            content: "visible",
            evidence: .userProvided
        )
        let bindingRoot = PromptModule(
            role: .instruction,
            content: "bound",
            evidence: .userProvided
        )
        let sourceAssetID = AssetID()
        let sourceDerived = PromptModule(
            category: .style,
            content: "derived",
            sourceAssetID: sourceAssetID,
            evidence: .observable
        )
        let recipe = Recipe(
            name: "Binding root",
            bindings: [
                RecipeInputBinding(
                    moduleID: bindingRoot.id,
                    role: bindingRoot.role,
                    order: 0
                )
            ],
            target: target
        )
        let occurrenceNode = CanvasNode(
            promptModuleID: occurrenceRoot.id,
            frame: WorldRect(x: 0, y: 0, width: 280, height: 160)
        )
        let frozenSnapshot = CompiledPromptSnapshot(
            recipeID: RecipeID(),
            target: target,
            moduleInputs: [
                ModuleInputSnapshot(
                    moduleID: orphan.id,
                    revision: orphan.revision,
                    role: orphan.role,
                    resolvedContent: orphan.content,
                    evidence: orphan.evidence
                )
            ],
            baseText: orphan.content,
            finalText: orphan.content,
            override: nil,
            sourceModuleIDs: [orphan.id],
            warnings: []
        )
        let changedAt = Date(timeIntervalSince1970: 678)
        var workspace = Workspace(
            title: "Module repair",
            promptModules: [orphan, occurrenceRoot, bindingRoot, sourceDerived],
            recipes: [recipe],
            compiledPrompts: [frozenSnapshot],
            canvasNodes: [occurrenceNode]
        )
        let originalSnapshots = workspace.compiledPrompts

        let first = CanvasNodeRemovalPolicy.pruneOrphanedSourceLessPromptModules(
            in: &workspace,
            changedAt: changedAt
        )

        XCTAssertEqual(first.removedPromptModuleIDs, [orphan.id])
        XCTAssertEqual(
            Set(workspace.promptModules.map(\.id)),
            [occurrenceRoot.id, bindingRoot.id, sourceDerived.id]
        )
        XCTAssertEqual(workspace.recipes, [recipe])
        XCTAssertEqual(workspace.compiledPrompts, originalSnapshots)
        XCTAssertEqual(workspace.updatedAt, changedAt)

        let normalizedWorkspace = workspace
        let second = CanvasNodeRemovalPolicy.pruneOrphanedSourceLessPromptModules(
            in: &workspace,
            changedAt: Date(timeIntervalSince1970: 999)
        )

        XCTAssertEqual(second, .empty)
        XCTAssertEqual(workspace, normalizedWorkspace)
    }

    func testTextBlockIsRemovedOnlyAfterItsLastCanvasOccurrence() {
        let note = TextBlock(text: "Keep together")
        let first = CanvasNode(
            textBlockID: note.id,
            frame: WorldRect(x: 0, y: 0, width: 280, height: 180)
        )
        let second = CanvasNode(
            textBlockID: note.id,
            frame: WorldRect(x: 320, y: 0, width: 280, height: 180)
        )
        var workspace = Workspace(
            title: "Notes",
            textBlocks: [note],
            canvasNodes: [first, second]
        )

        let firstRemoval = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [first.id],
            from: &workspace
        )
        XCTAssertTrue(firstRemoval.removedTextBlockIDs.isEmpty)
        XCTAssertEqual(workspace.textBlocks, [note])

        let secondRemoval = CanvasNodeRemovalPolicy.remove(
            nodeIDs: [second.id],
            from: &workspace
        )
        XCTAssertEqual(secondRemoval.removedTextBlockIDs, [note.id])
        XCTAssertTrue(workspace.textBlocks.isEmpty)
    }

    private func makeGenerator(name: String) -> (recipe: Recipe, generator: Generator) {
        let recipe = Recipe(name: "\(name) Recipe", target: target)
        let generator = Generator(name: name, recipeID: recipe.id, target: target)
        return (recipe, generator)
    }

    private var target: CompileTarget {
        CompileTarget(providerID: "test", modelID: "model")
    }

    private func generatorNode(_ generator: Generator, x: Double = 0) -> CanvasNode {
        CanvasNode(
            generatorID: generator.id,
            frame: WorldRect(x: x, y: 0, width: 320, height: 260)
        )
    }
}
