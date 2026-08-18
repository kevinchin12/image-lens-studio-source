import Foundation

public enum GeneratorReferenceConnectionPolicy {
    public static func sourceGeneratorID(
        for asset: Asset,
        generations: [GenerationRecord]
    ) -> GeneratorID? {
        generations.first(where: { generation in
            generation.id == asset.sourceGenerationID
                || generation.outputAssetIDs.contains(asset.id)
        })?.generatorID
    }

    public static func allowsConnection(
        asset: Asset,
        to targetGeneratorID: GeneratorID,
        generations: [GenerationRecord]
    ) -> Bool {
        sourceGeneratorID(for: asset, generations: generations) != targetGeneratorID
    }
}
