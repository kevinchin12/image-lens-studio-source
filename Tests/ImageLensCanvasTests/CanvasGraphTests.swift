import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class CanvasGraphTests: XCTestCase {
    func testValidatorRequiresOutputToInputAndExactPromptRole() {
        let module = PromptModule(
            role: .visual(.style),
            content: "editorial collage",
            evidence: .observable
        )
        let recipeID = RecipeID()
        let validator = ConnectionValidator()

        let valid = validator.validate(
            source: .moduleOutput(module),
            target: .recipeInput(recipeID, role: .visual(.style))
        )
        let wrongCategory = validator.validate(
            source: .moduleOutput(module),
            target: .recipeInput(recipeID, role: .visual(.camera))
        )
        let reversed = validator.validate(
            source: .recipeInput(recipeID, role: .visual(.style)),
            target: .moduleOutput(module)
        )

        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(wrongCategory.issues, [
            .incompatibleValue(
                source: .promptModule(.visual(.style)),
                target: .promptModule(.visual(.camera))
            )
        ])
        XCTAssertEqual(reversed.issues, [.sourceMustBeOutput, .targetMustBeInput])
    }

    func testInstructionOnlyConnectsToInstructionInput() {
        let instruction = PromptModule(
            role: .instruction,
            content: "leave generous negative space",
            evidence: .userProvided
        )
        let recipeID = RecipeID()
        let validator = ConnectionValidator()

        XCTAssertTrue(
            validator.validate(
                source: .moduleOutput(instruction),
                target: .recipeInput(recipeID, role: .instruction)
            ).isValid
        )
        XCTAssertFalse(
            validator.validate(
                source: .moduleOutput(instruction),
                target: .recipeInput(recipeID, role: .visual(.composition))
            ).isValid
        )
    }

    func testValidatorRejectsDuplicateBindingAndSingleInputOverflow() {
        let module = PromptModule(
            role: .visual(.camera),
            content: "85mm portrait lens",
            evidence: .inferred
        )
        let binding = RecipeInputBinding(moduleID: module.id, role: module.role, order: 0)
        let recipe = Recipe(
            name: "Portrait",
            bindings: [binding],
            target: CompileTarget(providerID: "test", modelID: "model")
        )
        let generator = Generator(
            name: "Output",
            recipeID: recipe.id,
            target: recipe.target
        )
        let workspace = Workspace(
            title: "Graph",
            promptModules: [module],
            recipes: [recipe],
            generators: [generator]
        )
        let projection = GraphProjection(workspace: workspace)
        let validator = ConnectionValidator()

        let duplicate = validator.validate(
            source: .moduleOutput(module),
            target: .recipeInput(recipe.id, role: module.role),
            existingEdges: projection.edges
        )
        XCTAssertEqual(duplicate.issues, [.duplicateBinding])

        let otherRecipeID = RecipeID()
        let overflow = validator.validate(
            source: .recipeOutput(otherRecipeID),
            target: .generatorRecipeInput(generator.id),
            existingEdges: projection.edges
        )
        XCTAssertEqual(
            overflow.issues,
            [.cardinalityExceeded(GraphPortProjection.generatorRecipeInput(generator.id).id)]
        )
    }

    func testGraphProjectionDerivesDependenciesAndLineageFromWorkspace() {
        let sourceAsset = Asset(
            kind: .source,
            displayName: "Source",
            relativePath: "assets/original/source.png",
            mimeType: "image/png"
        )
        let outputAsset = Asset(
            kind: .generated,
            displayName: "Output",
            relativePath: "assets/derived/output.png",
            mimeType: "image/png"
        )
        let module = PromptModule(
            role: .visual(.environment),
            content: "quiet foggy shoreline",
            sourceAssetID: sourceAsset.id,
            evidence: .observable
        )
        let recipeBinding = RecipeInputBinding(
            moduleID: module.id,
            role: module.role,
            order: 0,
            priority: .primary
        )
        let recipe = Recipe(
            name: "Atmosphere",
            bindings: [recipeBinding],
            target: CompileTarget(providerID: "test", modelID: "model")
        )
        let assetBinding = GeneratorAssetBinding(
            assetID: sourceAsset.id,
            role: .composition,
            order: 0
        )
        let generator = Generator(
            name: "Generator",
            recipeID: recipe.id,
            target: recipe.target,
            assetBindings: [assetBinding]
        )
        let generation = GenerationRecord(
            generatorID: generator.id,
            recipeID: recipe.id,
            promptSnapshotID: CompiledPromptID(),
            providerID: "test",
            modelID: "model",
            aspectRatio: "1:1",
            state: .succeeded,
            outputAssetIDs: [outputAsset.id]
        )
        let workspace = Workspace(
            title: "Projection",
            assets: [sourceAsset, outputAsset],
            promptModules: [module],
            recipes: [recipe],
            generators: [generator],
            generations: [generation]
        )

        let projection = GraphProjection(workspace: workspace)

        XCTAssertEqual(projection.edges.count, 5)
        XCTAssertEqual(projection.edges.filter(\.isEditable).count, 2)
        XCTAssertTrue(projection.edges.contains { edge in
            edge.id == .moduleSource(moduleID: module.id, assetID: sourceAsset.id)
                && edge.role == .lineage(.moduleSource)
        })
        XCTAssertTrue(projection.edges.contains { edge in
            edge.id == .recipeBinding(recipeID: recipe.id, bindingID: recipeBinding.id)
                && edge.role == .dependency(.recipeBinding(recipeBinding.id))
        })
        XCTAssertTrue(projection.edges.contains { edge in
            edge.id == .generatorRecipe(generatorID: generator.id, recipeID: recipe.id)
                && edge.role == .dependency(.generatorRecipe)
        })
        XCTAssertTrue(projection.edges.contains { edge in
            edge.id == .generatorAsset(generatorID: generator.id, bindingID: assetBinding.id)
                && edge.role == .dependency(.generatorAsset(assetBinding.id))
        })
        XCTAssertTrue(projection.edges.contains { edge in
            edge.id == .generationOutput(generationID: generation.id, assetID: outputAsset.id)
                && edge.role == .lineage(.generationOutput(generation.id))
                && edge.source.id.owner == .generator(generator.id)
        })
    }

    func testImageAndVideoOutputsValidateAgainstGenericMediaReferenceInput() {
        let image = Asset(
            kind: .source,
            displayName: "still.png",
            relativePath: "assets/original/still.png",
            mimeType: "image/png"
        )
        let video = Asset(
            kind: .source,
            displayName: "clip.mp4",
            relativePath: "assets/original/clip.mp4",
            mimeType: "video/mp4"
        )
        let generatorID = GeneratorID()
        let projection = GraphProjection(
            workspace: Workspace(title: "Media", assets: [image, video])
        )
        let imageOutput = projection.port(
            id: GraphPortID(owner: .asset(image.id), key: .assetOutput)
        )
        let output = projection.port(
            id: GraphPortID(owner: .asset(video.id), key: .assetOutput)
        )

        XCTAssertEqual(imageOutput?.valueType, .imageAsset)
        XCTAssertEqual(output?.valueType, .videoAsset)
        let target = GraphPortProjection.generatorAssetInput(generatorID, role: .identity)
        XCTAssertEqual(target.valueType, .mediaAsset)
        XCTAssertTrue(ConnectionValidator().validate(
            source: try! XCTUnwrap(imageOutput),
            target: target
        ).isValid)
        XCTAssertTrue(ConnectionValidator().validate(
            source: try! XCTUnwrap(output),
            target: target
        ).isValid)
    }

    func testGenericMediaInputDoesNotAcceptPromptValues() {
        let module = PromptModule(
            role: .instruction,
            content: "Keep the subject centered",
            evidence: .userProvided
        )
        let target = GraphPortProjection.generatorAssetInput(GeneratorID(), role: .identity)

        XCTAssertEqual(
            ConnectionValidator().validate(
                source: .moduleOutput(module),
                target: target
            ).issues,
            [
                .incompatibleValue(
                    source: .promptModule(.instruction),
                    target: .mediaAsset
                )
            ]
        )
    }

    func testCanvasNodeOwnerBridgeDistinguishesGeneratorFromLegacyRun() {
        let target = CompileTarget(providerID: "test", modelID: "model")
        let recipe = Recipe(name: "Input", target: target)
        let generator = Generator(name: "Action", recipeID: recipe.id, target: target)
        let run = GenerationRecord(
            recipeID: recipe.id,
            promptSnapshotID: CompiledPromptID(),
            providerID: "test",
            modelID: "model",
            aspectRatio: "1:1"
        )
        let generatorNode = CanvasNode(
            generatorID: generator.id,
            frame: WorldRect(x: 0, y: 0, width: 320, height: 400)
        )
        let runNode = CanvasNode(
            generationID: run.id,
            frame: WorldRect(x: 400, y: 0, width: 320, height: 400)
        )
        let workspace = Workspace(
            title: "Bridge",
            recipes: [recipe],
            generators: [generator],
            generations: [run],
            canvasNodes: [generatorNode, runNode]
        )
        let projection = GraphProjection(workspace: workspace)

        XCTAssertEqual(
            GraphEntityReference(node: generatorNode, workspace: workspace),
            .generator(generator.id)
        )
        XCTAssertEqual(
            GraphEntityReference(node: runNode, workspace: workspace),
            .generationRun(run.id)
        )
        XCTAssertFalse(projection.ports(for: .generator(generator.id)).isEmpty)
    }
}
