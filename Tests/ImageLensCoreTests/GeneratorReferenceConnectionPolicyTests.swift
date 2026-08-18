import XCTest
@testable import ImageLensCore

final class GeneratorReferenceConnectionPolicyTests: XCTestCase {
    func testGeneratedOutputCannotReferenceItsOwnGenerator() {
        let generatorID = GeneratorID()
        let assetID = AssetID()
        let generation = makeGeneration(generatorID: generatorID, outputAssetIDs: [assetID])
        let asset = makeGeneratedAsset(id: assetID, sourceGenerationID: generation.id)

        XCTAssertEqual(
            GeneratorReferenceConnectionPolicy.sourceGeneratorID(
                for: asset,
                generations: [generation]
            ),
            generatorID
        )
        XCTAssertFalse(
            GeneratorReferenceConnectionPolicy.allowsConnection(
                asset: asset,
                to: generatorID,
                generations: [generation]
            )
        )
    }

    func testGeneratedOutputCanReferenceAnotherGenerator() {
        let sourceGeneratorID = GeneratorID()
        let targetGeneratorID = GeneratorID()
        let generation = makeGeneration(generatorID: sourceGeneratorID)
        let asset = makeGeneratedAsset(sourceGenerationID: generation.id)

        XCTAssertTrue(
            GeneratorReferenceConnectionPolicy.allowsConnection(
                asset: asset,
                to: targetGeneratorID,
                generations: [generation]
            )
        )
    }

    func testLegacyOutputWithoutSourceGenerationStillCannotReferenceItsOwnGenerator() {
        let generatorID = GeneratorID()
        let assetID = AssetID()
        let generation = makeGeneration(generatorID: generatorID, outputAssetIDs: [assetID])
        let asset = makeGeneratedAsset(id: assetID, sourceGenerationID: nil)

        XCTAssertFalse(
            GeneratorReferenceConnectionPolicy.allowsConnection(
                asset: asset,
                to: generatorID,
                generations: [generation]
            )
        )
    }

    func testSourceMaterialAliasPreservesSelfReferenceGuard() {
        let generatorID = GeneratorID()
        let generation = makeGeneration(generatorID: generatorID)
        let asset = makeGeneratedAsset(sourceGenerationID: generation.id)
            .sourceMaterialAlias()

        XCTAssertFalse(
            GeneratorReferenceConnectionPolicy.allowsConnection(
                asset: asset,
                to: generatorID,
                generations: [generation]
            )
        )
    }

    func testImportedMediaWithoutGenerationLineageRemainsConnectable() {
        let asset = Asset(
            kind: .source,
            state: .ready,
            isSavedToLibrary: true,
            displayName: "reference.png",
            relativePath: "assets/original/reference.png",
            mimeType: "image/png"
        )

        XCTAssertTrue(
            GeneratorReferenceConnectionPolicy.allowsConnection(
                asset: asset,
                to: GeneratorID(),
                generations: []
            )
        )
    }

    private func makeGeneration(
        generatorID: GeneratorID,
        outputAssetIDs: [AssetID] = []
    ) -> GenerationRecord {
        GenerationRecord(
            generatorID: generatorID,
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: "google-gemini",
            modelID: "test-model",
            aspectRatio: "16:9",
            state: .succeeded,
            outputAssetIDs: outputAssetIDs
        )
    }

    private func makeGeneratedAsset(
        id: AssetID = AssetID(),
        sourceGenerationID: GenerationID?
    ) -> Asset {
        Asset(
            id: id,
            kind: .generated,
            state: .ready,
            isSavedToLibrary: false,
            displayName: "result.png",
            relativePath: "assets/derived/result.png",
            mimeType: "image/png",
            sourceGenerationID: sourceGenerationID
        )
    }
}
