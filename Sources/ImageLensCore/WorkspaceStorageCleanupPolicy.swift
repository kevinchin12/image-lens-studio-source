import Foundation

/// Determines which generated assets are currently safe to detach from a workspace.
///
/// Generation history is intentionally treated as a soft reference: a result that is
/// only present in `GenerationRecord.outputAssetIDs` may be cleaned. Canvas placement,
/// the material library, active generator bindings, analysis provenance, and compiled
/// prompt evidence are strong references and keep the asset available.
public enum WorkspaceStorageCleanupPolicy {
    public static func removableGeneratedAssetIDs(in workspace: Workspace) -> [AssetID] {
        let stronglyReferencedIDs = stronglyReferencedAssetIDs(in: workspace)

        return workspace.assets.compactMap { asset in
            guard asset.kind == .generated,
                  asset.provenance == .generated,
                  !stronglyReferencedIDs.contains(asset.id),
                  !asset.usages.contains(.material),
                  !asset.usages.contains(.reference),
                  !asset.usages.contains(.archived) else {
                return nil
            }
            return asset.id
        }
    }

    public static func removingGeneratedAssets(
        _ assetIDs: Set<AssetID>,
        from workspace: Workspace
    ) -> Workspace {
        let currentlyRemovable = Set(removableGeneratedAssetIDs(in: workspace))
        let removableIDs = assetIDs.intersection(currentlyRemovable)
        guard !removableIDs.isEmpty else { return workspace }

        var result = workspace
        result.assets.removeAll { removableIDs.contains($0.id) }
        for index in result.generations.indices {
            result.generations[index].outputAssetIDs.removeAll {
                removableIDs.contains($0)
            }
        }
        return result
    }

    public static func stronglyReferencedAssetIDs(in workspace: Workspace) -> Set<AssetID> {
        var result = Set<AssetID>()

        result.formUnion(workspace.canvasNodes.compactMap(\.imageAssetID))
        result.formUnion(
            workspace.generators.flatMap { generator in
                generator.assetBindings.map(\.assetID)
            }
        )
        result.formUnion(workspace.generators.compactMap { $0.imageEdit?.sourceAssetID })
        result.formUnion(workspace.generations.compactMap { $0.imageEditSnapshot?.sourceAssetID })
        result.formUnion(workspace.promptModules.compactMap(\.sourceAssetID))
        result.formUnion(workspace.analysisSnapshots.map(\.assetID))
        result.formUnion(
            workspace.compiledPrompts.flatMap { snapshot in
                snapshot.moduleInputs.compactMap(\.sourceAssetID)
            }
        )
        result.formUnion(
            workspace.jobs.compactMap { job in
                guard job.kind == .analysis else { return nil }
                return AssetID(job.subjectID)
            }
        )
        result.formUnion(
            workspace.assets.compactMap { asset in
                guard asset.isSavedToLibrary
                        || asset.usages.contains(.material)
                        || asset.usages.contains(.reference)
                        || asset.usages.contains(.archived) else {
                    return nil
                }
                return asset.id
            }
        )

        return result
    }
}
