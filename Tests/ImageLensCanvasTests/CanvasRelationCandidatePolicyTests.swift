import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class CanvasRelationCandidatePolicyTests: XCTestCase {
    func testReferenceAssetsDeduplicateOccurrencesAndPreserveWorkspaceOrder() {
        let firstInWorkspace = asset(.source, name: "First")
        let secondInWorkspace = asset(.source, name: "Second")
        let secondNode = imageNode(secondInWorkspace.id)
        let secondDuplicate = imageNode(secondInWorkspace.id)
        let firstNode = imageNode(firstInWorkspace.id)
        let recipe = Recipe(name: "Assets", target: target)
        let generator = Generator(
            name: "Assets",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Assets",
            assets: [firstInWorkspace, secondInWorkspace],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [secondNode, secondDuplicate, firstNode]
        )

        let candidates = CanvasRelationCandidatePolicy.referenceAssets(
            in: workspace,
            generator: generator
        )

        XCTAssertEqual(
            candidates.availableOnCanvasIDs,
            [firstInWorkspace.id, secondInWorkspace.id]
        )
        XCTAssertTrue(candidates.boundOnCanvasIDs.isEmpty)
        XCTAssertTrue(candidates.boundOffCanvasIDs.isEmpty)
    }

    func testGeneratedAssetOnCanvasIsAvailable() {
        let source = asset(.source, name: "Source")
        let generated = asset(.generated, name: "Generated")
        let recipe = Recipe(name: "Generated", target: target)
        let generator = Generator(
            name: "Generated",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Generated",
            assets: [source, generated],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [imageNode(source.id), imageNode(generated.id)]
        )

        let candidates = CanvasRelationCandidatePolicy.referenceAssets(
            in: workspace,
            generator: generator
        )

        XCTAssertEqual(candidates.availableOnCanvasIDs, [source.id, generated.id])
    }

    func testVideoAssetOnCanvasIsAvailableAsMediaReference() {
        let image = asset(.source, name: "Image")
        let video = Asset(
            kind: .source,
            displayName: "Clip",
            relativePath: "assets/clip.mp4",
            mimeType: "video/mp4"
        )
        let recipe = Recipe(name: "Media", target: target)
        let generator = Generator(name: "Media", recipeID: recipe.id, target: target)
        let workspace = Workspace(
            title: "Media",
            assets: [video, image],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [imageNode(video.id), imageNode(image.id)]
        )

        let candidates = CanvasRelationCandidatePolicy.referenceAssets(
            in: workspace,
            generator: generator
        )

        XCTAssertEqual(candidates.availableOnCanvasIDs, [video.id, image.id])
    }

    func testReferenceBindingsSeparateOnCanvasAndOffCanvasAssets() {
        let available = asset(.source, name: "Available")
        let boundOnCanvas = asset(.source, name: "Bound here")
        let boundOffCanvas = asset(.generated, name: "Bound elsewhere")
        let recipe = Recipe(name: "Bindings", target: target)
        let generator = Generator(
            name: "Bindings",
            recipeID: recipe.id,
            target: target,
            assetBindings: [
                GeneratorAssetBinding(
                    assetID: boundOnCanvas.id,
                    role: .style,
                    order: 0
                ),
                GeneratorAssetBinding(
                    assetID: boundOffCanvas.id,
                    role: .composition,
                    order: 1
                ),
                GeneratorAssetBinding(
                    assetID: boundOffCanvas.id,
                    role: .palette,
                    order: 2
                )
            ]
        )
        let workspace = Workspace(
            title: "Bindings",
            assets: [available, boundOnCanvas, boundOffCanvas],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [imageNode(available.id), imageNode(boundOnCanvas.id)]
        )

        let candidates = CanvasRelationCandidatePolicy.referenceAssets(
            in: workspace,
            generator: generator
        )

        XCTAssertEqual(candidates.availableOnCanvasIDs, [available.id])
        XCTAssertEqual(candidates.boundOnCanvasIDs, [boundOnCanvas.id])
        XCTAssertEqual(candidates.boundOffCanvasIDs, [boundOffCanvas.id])
    }

    func testReferenceAssetsIgnoreWrongTypedAndDanglingNodes() {
        let validAsset = asset(.source, name: "Valid")
        let danglingAssetID = AssetID()
        let wrongTypedNode = CanvasNode(
            kind: .module,
            entityID: validAsset.id.rawValue,
            frame: frame
        )
        let danglingImageNode = imageNode(danglingAssetID)
        let recipe = Recipe(name: "Typed", target: target)
        let generator = Generator(
            name: "Typed",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Typed",
            assets: [validAsset],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [wrongTypedNode, danglingImageNode]
        )

        let candidates = CanvasRelationCandidatePolicy.referenceAssets(
            in: workspace,
            generator: generator
        )

        XCTAssertEqual(
            candidates,
            CanvasReferenceAssetCandidates(
                availableOnCanvasIDs: [],
                boundOnCanvasIDs: [],
                boundOffCanvasIDs: []
            )
        )
    }

    func testEmptyCanvasDoesNotExposeWorkspaceAssets() {
        let existing = asset(.source, name: "Library only")
        let recipe = Recipe(name: "Empty", target: target)
        let generator = Generator(
            name: "Empty",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Empty",
            assets: [existing],
            recipes: [recipe],
            generators: [generator]
        )

        let candidates = CanvasRelationCandidatePolicy.referenceAssets(
            in: workspace,
            generator: generator
        )

        XCTAssertTrue(candidates.availableOnCanvasIDs.isEmpty)
        XCTAssertTrue(candidates.boundOnCanvasIDs.isEmpty)
        XCTAssertTrue(candidates.boundOffCanvasIDs.isEmpty)
    }

    func testCollapsedGenerationGroupMemberRemainsAvailable() {
        let generated = asset(.generated, name: "Collapsed result")
        let memberNode = imageNode(generated.id)
        let group = CanvasGenerationGroup(
            generatorID: nil,
            memberNodeIDs: [memberNode.id],
            origin: .zero,
            isCollapsed: true
        )
        let recipe = Recipe(name: "Collapsed", target: target)
        let generator = Generator(
            name: "Collapsed",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Collapsed",
            assets: [generated],
            recipes: [recipe],
            generators: [generator],
            generationGroups: [group],
            canvasNodes: [memberNode]
        )

        let candidates = CanvasRelationCandidatePolicy.referenceAssets(
            in: workspace,
            generator: generator
        )

        XCTAssertEqual(candidates.availableOnCanvasIDs, [generated.id])
    }

    func testPromptModulesUseSameTypedOccurrenceAndBindingRules() {
        let available = promptModule("Available")
        let boundOnCanvas = promptModule("Bound here")
        let boundOffCanvas = promptModule("Bound elsewhere")
        let recipe = Recipe(
            name: "Modules",
            bindings: [
                RecipeInputBinding(
                    moduleID: boundOnCanvas.id,
                    role: boundOnCanvas.role,
                    order: 0
                ),
                RecipeInputBinding(
                    moduleID: boundOffCanvas.id,
                    role: boundOffCanvas.role,
                    order: 1
                ),
                RecipeInputBinding(
                    moduleID: boundOffCanvas.id,
                    role: boundOffCanvas.role,
                    order: 2
                )
            ],
            target: target
        )
        let wrongTypedNode = CanvasNode(
            kind: .image,
            entityID: PromptModuleID().rawValue,
            frame: frame
        )
        let danglingModuleNode = moduleNode(PromptModuleID())
        let workspace = Workspace(
            title: "Modules",
            promptModules: [available, boundOnCanvas, boundOffCanvas],
            recipes: [recipe],
            canvasNodes: [
                moduleNode(boundOnCanvas.id),
                moduleNode(available.id),
                moduleNode(available.id),
                wrongTypedNode,
                danglingModuleNode
            ]
        )

        let candidates = CanvasRelationCandidatePolicy.promptModules(
            in: workspace,
            recipe: recipe
        )

        XCTAssertEqual(candidates.availableOnCanvasIDs, [available.id])
        XCTAssertEqual(candidates.boundOnCanvasIDs, [boundOnCanvas.id])
        XCTAssertEqual(candidates.boundOffCanvasIDs, [boundOffCanvas.id])
    }

    func testPromptModulesAreEmptyWithoutModuleOccurrencesOrBindings() {
        let module = promptModule("Library only")
        let recipe = Recipe(name: "Empty modules", target: target)
        let workspace = Workspace(
            title: "Empty modules",
            promptModules: [module],
            recipes: [recipe],
            canvasNodes: [
                CanvasNode(
                    kind: .recipe,
                    entityID: module.id.rawValue,
                    frame: frame
                )
            ]
        )

        let candidates = CanvasRelationCandidatePolicy.promptModules(
            in: workspace,
            recipe: recipe
        )

        XCTAssertEqual(
            candidates,
            CanvasPromptModuleCandidates(
                availableOnCanvasIDs: [],
                boundOnCanvasIDs: [],
                boundOffCanvasIDs: []
            )
        )
    }

    private var target: CompileTarget {
        CompileTarget(providerID: "test", modelID: "model")
    }

    private var frame: WorldRect {
        WorldRect(x: 0, y: 0, width: 100, height: 100)
    }

    private func asset(_ kind: AssetKind, name: String) -> Asset {
        Asset(
            kind: kind,
            displayName: name,
            relativePath: "assets/\(name).png",
            mimeType: "image/png"
        )
    }

    private func promptModule(_ content: String) -> PromptModule {
        PromptModule(
            role: .instruction,
            content: content,
            evidence: .userProvided
        )
    }

    private func imageNode(_ assetID: AssetID) -> CanvasNode {
        CanvasNode(imageAssetID: assetID, frame: frame)
    }

    private func moduleNode(_ moduleID: PromptModuleID) -> CanvasNode {
        CanvasNode(promptModuleID: moduleID, frame: frame)
    }
}
