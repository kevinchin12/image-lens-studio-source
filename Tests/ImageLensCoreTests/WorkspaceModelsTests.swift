import ImageLensCore
import XCTest

final class WorkspaceModelsTests: XCTestCase {
    func testNewGenerationParametersDefaultToWideCanvas() {
        XCTAssertEqual(GenerationParameters().aspectRatio, "16:9")
    }

    func testGeneratorPromptTextRoundTrips() throws {
        let generator = Generator(
            name: "海报生成",
            recipeID: RecipeID(),
            promptText: "深蓝夜景\n银色汽车",
            target: CompileTarget(providerID: "gemini", modelID: "image-model")
        )

        let data = try JSONEncoder().encode(generator)
        let decoded = try JSONDecoder().decode(Generator.self, from: data)

        XCTAssertEqual(decoded.promptText, generator.promptText)
        XCTAssertEqual(decoded, generator)
    }

    func testLegacyGeneratorWithoutPromptTextDecodesAsEmpty() throws {
        let generator = Generator(
            name: "旧生图节点",
            recipeID: RecipeID(),
            promptText: "legacy",
            target: CompileTarget(providerID: "gemini", modelID: "image-model")
        )
        let encoded = try JSONEncoder().encode(generator)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "promptText")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Generator.self, from: legacyData)

        XCTAssertEqual(decoded.promptText, "")
        XCTAssertNil(decoded.imageEdit)
    }

    func testImageEditConfigurationAndRunSnapshotRoundTrip() throws {
        let sourceAssetID = AssetID()
        let configuration = ImageEditConfiguration(
            sourceAssetID: sourceAssetID,
            maskRelativePath: "assets/derived/masks/edit-mask.png",
            maskPixelSize: PixelSize(width: 1200, height: 800),
            maskContentHash: "mask-hash"
        )
        let generator = Generator(
            name: "局部改图",
            recipeID: RecipeID(),
            target: CompileTarget(providerID: "gemini", modelID: "image-model"),
            imageEdit: configuration
        )
        let snapshot = ImageEditSnapshot(
            sourceAssetID: sourceAssetID,
            sourcePixelSize: PixelSize(width: 1200, height: 800),
            sourceContentHash: "source-hash",
            maskRelativePath: configuration.maskRelativePath,
            maskPixelSize: configuration.maskPixelSize,
            maskContentHash: configuration.maskContentHash
        )
        let generation = GenerationRecord(
            recipeID: generator.recipeID,
            promptSnapshotID: CompiledPromptID(),
            providerID: generator.target.providerID,
            modelID: generator.target.modelID,
            aspectRatio: "3:2",
            imageEditSnapshot: snapshot
        )

        XCTAssertEqual(
            try JSONDecoder().decode(Generator.self, from: JSONEncoder().encode(generator)),
            generator
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                GenerationRecord.self,
                from: JSONEncoder().encode(generation)
            ),
            generation
        )
    }

    func testGeneratedImageCanCreateLightweightIndependentSourceAlias() {
        let generationID = GenerationID()
        let generated = Asset(
            kind: .generated,
            state: .ready,
            isSavedToLibrary: false,
            displayName: "生成结果 1",
            relativePath: "assets/generated/result.webp",
            thumbnailRelativePath: "assets/thumbnails/result.webp",
            mimeType: "image/webp",
            pixelSize: PixelSize(width: 1024, height: 1536),
            contentHash: "same-bytes",
            sourceGenerationID: generationID
        )

        let source = generated.sourceMaterialAlias()

        XCTAssertNotEqual(source.id, generated.id)
        XCTAssertEqual(source.kind, .source)
        XCTAssertEqual(source.provenance, .generated)
        XCTAssertEqual(source.usages, [.material])
        XCTAssertEqual(source.state, .imported)
        XCTAssertTrue(source.isSavedToLibrary)
        XCTAssertTrue(source.supportsReversePrompt)
        XCTAssertEqual(source.relativePath, generated.relativePath)
        XCTAssertEqual(source.thumbnailRelativePath, generated.thumbnailRelativePath)
        XCTAssertEqual(source.contentHash, generated.contentHash)
        XCTAssertEqual(source.pixelSize, generated.pixelSize)
        XCTAssertEqual(source.sourceGenerationID, generationID)
        XCTAssertEqual(generated.kind, .generated)
        XCTAssertEqual(generated.provenance, .generated)
        XCTAssertEqual(generated.usages, [.result])
        XCTAssertEqual(generated.sourceGenerationID, generationID)
    }

    func testGeneratorAllowsOneAssetToServeSeveralReferenceRoles() {
        let sharedAssetID = AssetID()
        let secondAssetID = AssetID()
        let generator = Generator(
            name: "多角色参考",
            recipeID: RecipeID(),
            target: CompileTarget(providerID: "gemini", modelID: "image-model"),
            assetBindings: [
                GeneratorAssetBinding(assetID: sharedAssetID, role: .identity, order: 0),
                GeneratorAssetBinding(assetID: sharedAssetID, role: .palette, order: 1),
                GeneratorAssetBinding(assetID: secondAssetID, role: .style, order: 2)
            ]
        )

        XCTAssertEqual(generator.uniqueReferenceAssetIDs, [sharedAssetID, secondAssetID])
        XCTAssertEqual(generator.uniqueReferenceAssetCount, 2)
        XCTAssertTrue(generator.hasReferenceBinding(assetID: sharedAssetID, role: .identity))
        XCTAssertTrue(generator.hasReferenceBinding(assetID: sharedAssetID, role: .palette))
        XCTAssertFalse(generator.hasReferenceBinding(assetID: sharedAssetID, role: .environment))
    }

    func testCanvasOffersOnlyFourReferenceRolesWhileLegacyRolesRemainDecodable() throws {
        XCTAssertEqual(
            GeneratorAssetRole.assignableCases,
            [.identity, .environment, .style, .palette]
        )

        let legacyRoles = try JSONDecoder().decode(
            [GeneratorAssetRole].self,
            from: Data("[\"composition\",\"structure\"]".utf8)
        )
        XCTAssertEqual(legacyRoles, [.composition, .structure])
        XCTAssertEqual(
            try JSONDecoder().decode(
                GeneratorAssetRole.self,
                from: Data("\"general\"".utf8)
            ),
            .general
        )
    }

    func testPixelAspectRatioRequiresPositiveDimensions() throws {
        XCTAssertEqual(
            try XCTUnwrap(PixelSize(width: 1200, height: 800).aspectRatio),
            1.5,
            accuracy: 0.0001
        )
        XCTAssertNil(PixelSize(width: 0, height: 800).aspectRatio)
        XCTAssertNil(PixelSize(width: 1200, height: 0).aspectRatio)
        XCTAssertNil(PixelSize(width: -1, height: 800).aspectRatio)
    }

    func testAssetUsesPersistedPixelSizeAsItsAspectRatioSource() throws {
        let asset = Asset(
            kind: .source,
            displayName: "portrait.png",
            relativePath: "assets/original/portrait.png",
            mimeType: "image/png",
            pixelSize: PixelSize(width: 900, height: 1600)
        )

        XCTAssertEqual(
            try XCTUnwrap(asset.contentAspectRatio),
            9.0 / 16.0,
            accuracy: 0.0001
        )
    }

    func testAssetLibraryDefaultsMatchUserIntent() {
        let source = Asset(
            kind: .source,
            displayName: "reference.png",
            relativePath: "assets/original/reference.png",
            mimeType: "image/png"
        )
        let generated = Asset(
            kind: .generated,
            displayName: "result",
            relativePath: "assets/derived/result.jpg",
            mimeType: "image/jpeg"
        )

        XCTAssertTrue(source.isSavedToLibrary)
        XCTAssertEqual(source.provenance, .imported)
        XCTAssertEqual(source.usages, [.material])
        XCTAssertFalse(generated.isSavedToLibrary)
        XCTAssertEqual(generated.provenance, .generated)
        XCTAssertEqual(generated.usages, [.result])
    }

    func testSavedGeneratedAssetCanBeResultAndMaterialWithoutLosingProvenance() {
        let asset = Asset(
            kind: .generated,
            isSavedToLibrary: true,
            displayName: "kept-result.jpg",
            relativePath: "assets/derived/kept-result.jpg",
            mimeType: "image/jpeg",
            sourceGenerationID: GenerationID()
        )

        XCTAssertEqual(asset.provenance, .generated)
        XCTAssertEqual(asset.usages, [.material, .result])
        XCTAssertTrue(asset.isMaterial)
        XCTAssertTrue(asset.isResult)
        XCTAssertTrue(asset.supportsReversePrompt)
    }

    func testAssetUsageMutationHasStableOrderAndNoDuplicates() {
        var asset = Asset(
            kind: .generated,
            displayName: "result.jpg",
            relativePath: "assets/derived/result.jpg",
            mimeType: "image/jpeg"
        )

        asset.addUsage(.reference)
        asset.addUsage(.material)
        asset.addUsage(.reference)
        XCTAssertEqual(asset.usages, [.material, .result, .reference])

        asset.removeUsage(.result)
        XCTAssertEqual(asset.usages, [.material, .reference])
        XCTAssertFalse(asset.isResult)
    }

    func testLegacyAssetsDecodeWithKindBasedLibraryDefaults() throws {
        let source = Asset(
            kind: .source,
            displayName: "reference.png",
            relativePath: "assets/original/reference.png",
            mimeType: "image/png"
        )
        let generated = Asset(
            kind: .generated,
            displayName: "result",
            relativePath: "assets/derived/result.jpg",
            mimeType: "image/jpeg"
        )

        let decodedSource = try decodeAssetWithoutLibraryFlag(source)
        let decodedGenerated = try decodeAssetWithoutLibraryFlag(generated)

        XCTAssertTrue(decodedSource.isSavedToLibrary)
        XCTAssertFalse(decodedGenerated.isSavedToLibrary)
    }

    func testLegacyAssetsDecodeProvenanceAndUsageFromCompatibilityFields() throws {
        let source = Asset(
            kind: .source,
            displayName: "reference.png",
            relativePath: "assets/original/reference.png",
            mimeType: "image/png"
        )
        let keptGenerated = Asset(
            kind: .generated,
            isSavedToLibrary: true,
            displayName: "kept.jpg",
            relativePath: "assets/derived/kept.jpg",
            mimeType: "image/jpeg",
            sourceGenerationID: GenerationID()
        )

        let decodedSource = try decodeLegacyAsset(source)
        let decodedGenerated = try decodeLegacyAsset(keptGenerated)

        XCTAssertEqual(decodedSource.provenance, .imported)
        XCTAssertEqual(decodedSource.usages, [.material])
        XCTAssertEqual(decodedGenerated.provenance, .generated)
        XCTAssertEqual(decodedGenerated.usages, [.material, .result])
    }

    func testLegacyGenerationRecordDecodesWithoutDisplaySnapshots() throws {
        let record = GenerationRecord(
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: "gemini",
            modelID: "image-model",
            aspectRatio: "1:1",
            state: .succeeded,
            generatorNameSnapshot: "金币海报",
            displayTitle: "浮雕金币 · 第 3 次"
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(record)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "generatorNameSnapshot")
        object.removeValue(forKey: "displayTitle")
        object.removeValue(forKey: "mediaKind")
        object.removeValue(forKey: "imageEditSnapshot")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(GenerationRecord.self, from: legacyData)

        XCTAssertNil(decoded.generatorNameSnapshot)
        XCTAssertNil(decoded.displayTitle)
        XCTAssertEqual(decoded.outputAssetIDs, [])
        XCTAssertEqual(decoded.mediaKind, .image)
        XCTAssertNil(decoded.imageEditSnapshot)
    }

    func testLegacyGeneratorDecodesWithImageMediaKind() throws {
        let generator = Generator(
            name: "Legacy image generator",
            recipeID: RecipeID(),
            target: CompileTarget(providerID: "gemini", modelID: "image")
        )
        let encoded = try JSONEncoder().encode(generator)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "mediaKind")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Generator.self, from: legacyData)

        XCTAssertEqual(decoded.mediaKind, .image)
    }

    func testVideoGenerationMediaKindRoundTrips() throws {
        let generator = Generator(
            name: "Video generator",
            recipeID: RecipeID(),
            target: CompileTarget(providerID: "video-provider", modelID: "video-model"),
            mediaKind: .video
        )
        let generation = GenerationRecord(
            recipeID: generator.recipeID,
            promptSnapshotID: CompiledPromptID(),
            providerID: generator.target.providerID,
            modelID: generator.target.modelID,
            aspectRatio: "16:9",
            mediaKind: .video
        )

        XCTAssertEqual(
            try JSONDecoder().decode(Generator.self, from: JSONEncoder().encode(generator)),
            generator
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GenerationRecord.self, from: JSONEncoder().encode(generation)),
            generation
        )
    }

    func testGenerationVariationCountIsAlwaysClampedToOneThroughFour() throws {
        XCTAssertEqual(GenerationParameters(variationCount: 0).variationCount, 1)
        XCTAssertEqual(GenerationParameters(variationCount: 4).variationCount, 4)
        XCTAssertEqual(GenerationParameters(variationCount: 99).variationCount, 4)

        let tooLargeJSON = Data(
            #"{"aspectRatio":"16:9","variationCount":99,"providerOptions":{}}"#.utf8
        )
        let decoded = try JSONDecoder().decode(GenerationParameters.self, from: tooLargeJSON)
        XCTAssertEqual(decoded.variationCount, 4)

        let encoded = try JSONEncoder().encode(decoded)
        let roundTrip = try JSONDecoder().decode(GenerationParameters.self, from: encoded)
        XCTAssertEqual(roundTrip.variationCount, 4)
    }

    func testVideoDurationDefaultsToTenSecondsAndClampsToSupportedRange() {
        XCTAssertEqual(GenerationParameters().videoDurationSeconds, 10)
        XCTAssertEqual(
            GenerationParameters(providerOptions: ["durationSeconds": "3"]).videoDurationSeconds,
            3
        )
        XCTAssertEqual(
            GenerationParameters(providerOptions: ["durationSeconds": "2"]).videoDurationSeconds,
            3
        )
        XCTAssertEqual(
            GenerationParameters(providerOptions: ["durationSeconds": "11"]).videoDurationSeconds,
            10
        )
        XCTAssertEqual(
            GenerationParameters(providerOptions: ["durationSeconds": "invalid"]).videoDurationSeconds,
            10
        )
    }

    private func decodeAssetWithoutLibraryFlag(_ asset: Asset) throws -> Asset {
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(asset)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "isSavedToLibrary")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Asset.self, from: legacyData)
    }

    private func decodeLegacyAsset(_ asset: Asset) throws -> Asset {
        let encoded = try JSONEncoder().encode(asset)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "provenance")
        object.removeValue(forKey: "usages")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Asset.self, from: legacyData)
    }
}
