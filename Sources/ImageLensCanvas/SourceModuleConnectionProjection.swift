import Foundation
import ImageLensCore

/// Stable identity for a direct source-image-to-generator prompt connection.
public struct SourceModuleConnectionGroupID: Hashable, Sendable {
    public let assetID: AssetID
    public let generatorID: GeneratorID

    public init(assetID: AssetID, generatorID: GeneratorID) {
        self.assetID = assetID
        self.generatorID = generatorID
    }
}

/// Display-only aggregation of source modules that do not have a module node.
public struct SourceModuleConnectionGroup: Equatable, Identifiable, Sendable {
    public let id: SourceModuleConnectionGroupID
    public let moduleIDs: [PromptModuleID]

    public init(
        assetID: AssetID,
        generatorID: GeneratorID,
        moduleIDs: [PromptModuleID]
    ) {
        id = SourceModuleConnectionGroupID(
            assetID: assetID,
            generatorID: generatorID
        )
        self.moduleIDs = moduleIDs
    }

    public var assetID: AssetID { id.assetID }
    public var generatorID: GeneratorID { id.generatorID }
    public var count: Int { moduleIDs.count }
}

/// Derives aggregate direct-connection chrome from canonical workspace values.
///
/// A prompt module is represented by this projection only while it has no
/// `.module` canvas occurrence. The projection never materializes nodes or
/// changes recipe data.
public struct SourceModuleConnectionProjection: Equatable, Sendable {
    public let groups: [SourceModuleConnectionGroup]

    public init(workspace: Workspace) {
        let modulesByID = Dictionary(
            workspace.promptModules.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let recipesByID = Dictionary(
            workspace.recipes.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let materializedModuleIDs = Set(
            workspace.canvasNodes.compactMap { node in
                node.kind == .module ? node.promptModuleID : nil
            }
        )
        var result: [SourceModuleConnectionGroup] = []

        for generator in workspace.generators {
            guard let recipe = recipesByID[generator.recipeID] else { continue }

            var moduleIDsByAssetID: [AssetID: [PromptModuleID]] = [:]
            var assetOrder: [AssetID] = []
            var seenModuleIDs: Set<PromptModuleID> = []
            let orderedBindings = recipe.bindings.enumerated().sorted { lhs, rhs in
                if lhs.element.order != rhs.element.order {
                    return lhs.element.order < rhs.element.order
                }
                return lhs.offset < rhs.offset
            }

            for (_, binding) in orderedBindings {
                guard binding.isEnabled,
                      seenModuleIDs.insert(binding.moduleID).inserted,
                      !materializedModuleIDs.contains(binding.moduleID),
                      let module = modulesByID[binding.moduleID],
                      let assetID = module.sourceAssetID else {
                    continue
                }
                if moduleIDsByAssetID[assetID] == nil {
                    moduleIDsByAssetID[assetID] = []
                    assetOrder.append(assetID)
                }
                moduleIDsByAssetID[assetID, default: []].append(module.id)
            }

            for assetID in assetOrder {
                guard let moduleIDs = moduleIDsByAssetID[assetID],
                      !moduleIDs.isEmpty else {
                    continue
                }
                result.append(
                    SourceModuleConnectionGroup(
                        assetID: assetID,
                        generatorID: generator.id,
                        moduleIDs: moduleIDs
                    )
                )
            }
        }

        groups = result
    }
}
