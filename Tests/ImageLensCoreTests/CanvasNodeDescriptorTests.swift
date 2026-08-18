import XCTest
@testable import ImageLensCore

final class CanvasNodeDescriptorTests: XCTestCase {
    func testSourceImageProjectsAsAnalyzableMedia() {
        let asset = Asset(
            kind: .source,
            displayName: "source.png",
            relativePath: "source.png",
            mimeType: "image/png"
        )
        let node = CanvasNode(
            imageAssetID: asset.id,
            frame: WorldRect(x: 0, y: 0, width: 320, height: 240)
        )
        let workspace = Workspace(title: "Test", assets: [asset], canvasNodes: [node])

        let descriptor = CanvasNodeRegistry.descriptor(for: node, in: workspace)

        XCTAssertEqual(descriptor.typeID, .image)
        XCTAssertEqual(descriptor.family, .media)
        XCTAssertTrue(descriptor.supports(.analyzeImage))
        XCTAssertTrue(descriptor.supports(.useAsReference))
        XCTAssertFalse(descriptor.supports(.resize))
    }

    func testGeneratedResultAndMaterialAliasHaveDifferentCanvasFamilies() {
        let result = Asset(
            kind: .generated,
            displayName: "result.png",
            relativePath: "assets/derived/result.png",
            mimeType: "image/png"
        )
        let material = result.sourceMaterialAlias()

        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: result).family, .result)
        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: result).typeID, .generatedImage)
        XCTAssertFalse(CanvasNodeRegistry.descriptor(for: result).supports(.analyzeImage))
        XCTAssertFalse(CanvasNodeRegistry.descriptor(for: result).supports(.resize))

        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: material).family, .media)
        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: material).typeID, .image)
        XCTAssertTrue(CanvasNodeRegistry.descriptor(for: material).supports(.analyzeImage))
        XCTAssertFalse(CanvasNodeRegistry.descriptor(for: material).supports(.resize))
    }

    func testVideoAndTextAndActionUseGenericFamiliesWithoutChangingPersistedKinds() {
        let video = Asset(
            kind: .source,
            displayName: "clip.mp4",
            relativePath: "clip.mp4",
            mimeType: "video/mp4"
        )
        let target = CompileTarget(providerID: ProviderID("gemini"), modelID: "image")
        let module = PromptModule(
            role: .instruction,
            content: "Move slowly",
            evidence: .userProvided
        )
        let recipe = Recipe(name: "Input", target: target)
        let generator = Generator(
            name: "Image action",
            recipeID: recipe.id,
            target: target
        )
        let nodes = [
            CanvasNode(imageAssetID: video.id, frame: WorldRect(x: 0, y: 0, width: 320, height: 240)),
            CanvasNode(promptModuleID: module.id, frame: WorldRect(x: 0, y: 0, width: 280, height: 160)),
            CanvasNode(generatorID: generator.id, frame: WorldRect(x: 0, y: 0, width: 320, height: 400))
        ]
        let workspace = Workspace(
            title: "Test",
            assets: [video],
            promptModules: [module],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: nodes
        )

        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: nodes[0], in: workspace).typeID, .video)
        XCTAssertTrue(CanvasNodeRegistry.descriptor(for: nodes[0], in: workspace).supports(.playback))
        XCTAssertTrue(CanvasNodeRegistry.descriptor(for: nodes[0], in: workspace).supports(.useAsReference))
        XCTAssertFalse(CanvasNodeRegistry.descriptor(for: nodes[0], in: workspace).supports(.resize))
        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: nodes[1], in: workspace).family, .text)
        XCTAssertFalse(CanvasNodeRegistry.descriptor(for: nodes[1], in: workspace).supports(.resize))
        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: nodes[2], in: workspace).family, .action)
        XCTAssertFalse(CanvasNodeRegistry.descriptor(for: nodes[2], in: workspace).supports(.resize))
        XCTAssertEqual(
            nodes.map { $0.kind },
            [CanvasNodeKind.image, .module, .generation]
        )
    }

    func testNoteIsPlainTextWithoutConnectionCapability() {
        let block = TextBlock(text: "Remember this")
        let node = CanvasNode(
            textBlockID: block.id,
            frame: WorldRect(x: 0, y: 0, width: 280, height: 180)
        )
        let workspace = Workspace(
            title: "Note",
            textBlocks: [block],
            canvasNodes: [node]
        )

        let descriptor = CanvasNodeRegistry.descriptor(for: node, in: workspace)

        XCTAssertEqual(descriptor.typeID, .note)
        XCTAssertEqual(descriptor.family, .text)
        XCTAssertTrue(descriptor.supports(.editText))
        XCTAssertFalse(descriptor.supports(.connect))
    }

    func testVideoGeneratorAndGeneratedVideoProjectToVideoTypes() {
        let target = CompileTarget(providerID: "video-provider", modelID: "video-model")
        let recipe = Recipe(name: "Motion", target: target)
        let generator = Generator(
            name: "Motion",
            recipeID: recipe.id,
            target: target,
            mediaKind: .video
        )
        let generatorNode = CanvasNode(
            generatorID: generator.id,
            frame: WorldRect(x: 0, y: 0, width: 320, height: 400)
        )
        let result = Asset(
            kind: .generated,
            displayName: "result.mp4",
            relativePath: "assets/derived/result.mp4",
            mimeType: "video/mp4"
        )
        let workspace = Workspace(
            title: "Video",
            assets: [result],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [generatorNode]
        )

        XCTAssertEqual(
            CanvasNodeRegistry.descriptor(for: generatorNode, in: workspace).typeID,
            .videoGeneration
        )
        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: result).typeID, .generatedVideo)
        XCTAssertEqual(CanvasNodeRegistry.descriptor(for: result).family, .result)
    }
}
