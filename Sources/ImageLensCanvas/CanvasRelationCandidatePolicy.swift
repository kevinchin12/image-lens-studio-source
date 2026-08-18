import Foundation
import ImageLensCore

/// Reference-image identities grouped by current canvas presence and binding.
public struct CanvasReferenceAssetCandidates: Equatable, Sendable {
    public let availableOnCanvasIDs: [AssetID]
    public let boundOnCanvasIDs: [AssetID]
    public let boundOffCanvasIDs: [AssetID]

    public init(
        availableOnCanvasIDs: [AssetID],
        boundOnCanvasIDs: [AssetID],
        boundOffCanvasIDs: [AssetID]
    ) {
        self.availableOnCanvasIDs = availableOnCanvasIDs
        self.boundOnCanvasIDs = boundOnCanvasIDs
        self.boundOffCanvasIDs = boundOffCanvasIDs
    }
}

/// Prompt-module identities grouped by current canvas presence and binding.
public struct CanvasPromptModuleCandidates: Equatable, Sendable {
    public let availableOnCanvasIDs: [PromptModuleID]
    public let boundOnCanvasIDs: [PromptModuleID]
    public let boundOffCanvasIDs: [PromptModuleID]

    public init(
        availableOnCanvasIDs: [PromptModuleID],
        boundOnCanvasIDs: [PromptModuleID],
        boundOffCanvasIDs: [PromptModuleID]
    ) {
        self.availableOnCanvasIDs = availableOnCanvasIDs
        self.boundOnCanvasIDs = boundOnCanvasIDs
        self.boundOffCanvasIDs = boundOffCanvasIDs
    }
}

/// Derives relation-menu candidates from typed canvas occurrences.
///
/// Workspace entity order is preserved so menus stay stable as duplicate
/// occurrences are added, moved, or removed. Bindings do not make an off-canvas
/// entity an add candidate; they are reported separately for explicit cleanup.
public enum CanvasRelationCandidatePolicy {
    public static func referenceAssets(
        in workspace: Workspace,
        generator: Generator
    ) -> CanvasReferenceAssetCandidates {
        let onCanvasIDs = Set(workspace.canvasNodes.compactMap(\.imageAssetID))
        let boundIDs = Set(generator.assetBindings.map(\.assetID))
        var seenIDs: Set<AssetID> = []
        var availableOnCanvasIDs: [AssetID] = []
        var boundOnCanvasIDs: [AssetID] = []
        var boundOffCanvasIDs: [AssetID] = []

        for asset in workspace.assets
            where asset.supportsMediaReference && seenIDs.insert(asset.id).inserted {
            if onCanvasIDs.contains(asset.id) {
                if boundIDs.contains(asset.id) {
                    boundOnCanvasIDs.append(asset.id)
                } else {
                    availableOnCanvasIDs.append(asset.id)
                }
            } else if boundIDs.contains(asset.id) {
                boundOffCanvasIDs.append(asset.id)
            }
        }

        return CanvasReferenceAssetCandidates(
            availableOnCanvasIDs: availableOnCanvasIDs,
            boundOnCanvasIDs: boundOnCanvasIDs,
            boundOffCanvasIDs: boundOffCanvasIDs
        )
    }

    public static func promptModules(
        in workspace: Workspace,
        recipe: Recipe
    ) -> CanvasPromptModuleCandidates {
        let onCanvasIDs = Set(workspace.canvasNodes.compactMap(\.promptModuleID))
        let boundIDs = Set(recipe.bindings.map(\.moduleID))
        var seenIDs: Set<PromptModuleID> = []
        var availableOnCanvasIDs: [PromptModuleID] = []
        var boundOnCanvasIDs: [PromptModuleID] = []
        var boundOffCanvasIDs: [PromptModuleID] = []

        for module in workspace.promptModules where seenIDs.insert(module.id).inserted {
            if onCanvasIDs.contains(module.id) {
                if boundIDs.contains(module.id) {
                    boundOnCanvasIDs.append(module.id)
                } else {
                    availableOnCanvasIDs.append(module.id)
                }
            } else if boundIDs.contains(module.id) {
                boundOffCanvasIDs.append(module.id)
            }
        }

        return CanvasPromptModuleCandidates(
            availableOnCanvasIDs: availableOnCanvasIDs,
            boundOnCanvasIDs: boundOnCanvasIDs,
            boundOffCanvasIDs: boundOffCanvasIDs
        )
    }
}
