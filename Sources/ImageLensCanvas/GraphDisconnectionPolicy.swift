import Foundation
import ImageLensCore

/// A stable persisted binding removal derived from a visible graph connection.
///
/// Callers apply these operations by identity rather than by endpoint or
/// display text, so disconnecting one connection cannot remove a sibling that
/// happens to share the same source entity.
public enum GraphDisconnectionOperation: Equatable, Sendable {
    case recipeBinding(
        recipeID: RecipeID,
        bindingID: RecipeBindingID,
        moduleID: PromptModuleID
    )
    case generatorAssetBinding(
        generatorID: GeneratorID,
        bindingID: GeneratorAssetBindingID,
        assetID: AssetID
    )

    public var edgeID: GraphEdgeID {
        switch self {
        case let .recipeBinding(recipeID, bindingID, _):
            .recipeBinding(recipeID: recipeID, bindingID: bindingID)
        case let .generatorAssetBinding(generatorID, bindingID, _):
            .generatorAsset(generatorID: generatorID, bindingID: bindingID)
        }
    }
}

/// Pure-value transaction that a workspace owner can apply as one undo step.
public struct GraphDisconnectionPlan: Equatable, Sendable {
    public let operations: [GraphDisconnectionOperation]

    public init(operations: [GraphDisconnectionOperation]) {
        self.operations = operations
    }

    public var edgeIDs: [GraphEdgeID] {
        operations.map(\.edgeID)
    }

    /// Applies only the exact binding IDs captured by this plan.
    ///
    /// Every affected owner is revised once even when an aggregate plan removes
    /// several bindings from the same recipe. A stale operation is a no-op,
    /// which prevents an old UI selection from deleting a replacement binding.
    @discardableResult
    public func apply(
        to workspace: inout Workspace,
        updatedAt: Date = .now
    ) -> GraphDisconnectionApplication {
        var removedEdgeIDs: [GraphEdgeID] = []
        var affectedRecipeIDs: [RecipeID] = []
        var affectedGeneratorIDs: [GeneratorID] = []

        for operation in operations {
            switch operation {
            case let .recipeBinding(recipeID, bindingID, moduleID):
                guard let recipeIndex = workspace.recipes.firstIndex(
                    where: { $0.id == recipeID }
                ),
                let bindingIndex = workspace.recipes[recipeIndex].bindings.firstIndex(
                    where: { $0.id == bindingID && $0.moduleID == moduleID }
                ) else {
                    continue
                }
                workspace.recipes[recipeIndex].bindings.remove(at: bindingIndex)
                removedEdgeIDs.append(operation.edgeID)
                appendUnique(recipeID, to: &affectedRecipeIDs)

            case let .generatorAssetBinding(generatorID, bindingID, assetID):
                guard let generatorIndex = workspace.generators.firstIndex(
                    where: { $0.id == generatorID }
                ),
                let bindingIndex = workspace.generators[generatorIndex].assetBindings.firstIndex(
                    where: { $0.id == bindingID && $0.assetID == assetID }
                ) else {
                    continue
                }
                workspace.generators[generatorIndex].assetBindings.remove(at: bindingIndex)
                removedEdgeIDs.append(operation.edgeID)
                appendUnique(generatorID, to: &affectedGeneratorIDs)
            }
        }

        for recipeID in affectedRecipeIDs {
            guard let index = workspace.recipes.firstIndex(
                where: { $0.id == recipeID }
            ) else {
                continue
            }
            workspace.recipes[index].revision += 1
            workspace.recipes[index].updatedAt = updatedAt
        }
        for generatorID in affectedGeneratorIDs {
            guard let index = workspace.generators.firstIndex(
                where: { $0.id == generatorID }
            ) else {
                continue
            }
            workspace.generators[index].revision += 1
            workspace.generators[index].updatedAt = updatedAt
        }
        if !removedEdgeIDs.isEmpty {
            workspace.updatedAt = updatedAt
        }

        return GraphDisconnectionApplication(
            removedEdgeIDs: removedEdgeIDs,
            affectedRecipeIDs: affectedRecipeIDs,
            affectedGeneratorIDs: affectedGeneratorIDs
        )
    }

    private func appendUnique<ID: Equatable>(
        _ id: ID,
        to ids: inout [ID]
    ) {
        guard !ids.contains(id) else { return }
        ids.append(id)
    }
}

public struct GraphDisconnectionApplication: Equatable, Sendable {
    public let removedEdgeIDs: [GraphEdgeID]
    public let affectedRecipeIDs: [RecipeID]
    public let affectedGeneratorIDs: [GeneratorID]

    public init(
        removedEdgeIDs: [GraphEdgeID],
        affectedRecipeIDs: [RecipeID],
        affectedGeneratorIDs: [GeneratorID]
    ) {
        self.removedEdgeIDs = removedEdgeIDs
        self.affectedRecipeIDs = affectedRecipeIDs
        self.affectedGeneratorIDs = affectedGeneratorIDs
    }

    public var didChange: Bool {
        !removedEdgeIDs.isEmpty
    }
}

/// A request can address either one projected edge or selected members of the
/// display-only source-image aggregation.
public enum GraphDisconnectionRequest: Equatable, Sendable {
    case edge(GraphEdgeID)
    case sourceModuleGroup(
        id: SourceModuleConnectionGroupID,
        moduleIDs: [PromptModuleID]
    )
}

public enum GraphDisconnectionRejection: Equatable, Sendable {
    case readOnlyEdge(GraphEdgeID)
    case missingRecipe(RecipeID)
    case missingGenerator(GeneratorID)
    case missingRecipeBinding(recipeID: RecipeID, bindingID: RecipeBindingID)
    case missingGeneratorAssetBinding(
        generatorID: GeneratorID,
        bindingID: GeneratorAssetBindingID
    )
    case sourceModuleGroupNotFound(SourceModuleConnectionGroupID)
    case emptySourceModuleSelection(SourceModuleConnectionGroupID)
    case sourceModuleNotInGroup(
        groupID: SourceModuleConnectionGroupID,
        moduleID: PromptModuleID
    )
}

public enum GraphDisconnectionDecision: Equatable, Sendable {
    case accepted(GraphDisconnectionPlan)
    case rejected(GraphDisconnectionRejection)

    public var plan: GraphDisconnectionPlan? {
        guard case let .accepted(plan) = self else { return nil }
        return plan
    }
}

/// Resolves graph chrome into exact persisted binding identities without
/// mutating the workspace.
public enum GraphDisconnectionPolicy {
    public static func decide(
        _ request: GraphDisconnectionRequest,
        in workspace: Workspace
    ) -> GraphDisconnectionDecision {
        switch request {
        case let .edge(edgeID):
            decide(edgeID: edgeID, in: workspace)
        case let .sourceModuleGroup(groupID, moduleIDs):
            decide(
                sourceModuleGroupID: groupID,
                moduleIDs: moduleIDs,
                in: workspace
            )
        }
    }

    public static func decide(
        edgeID: GraphEdgeID,
        in workspace: Workspace
    ) -> GraphDisconnectionDecision {
        switch edgeID {
        case let .recipeBinding(recipeID, bindingID):
            guard let recipe = workspace.recipes.first(where: { $0.id == recipeID }) else {
                return .rejected(.missingRecipe(recipeID))
            }
            guard let binding = recipe.bindings.first(where: { $0.id == bindingID }) else {
                return .rejected(
                    .missingRecipeBinding(
                        recipeID: recipeID,
                        bindingID: bindingID
                    )
                )
            }
            return .accepted(
                GraphDisconnectionPlan(
                    operations: [
                        .recipeBinding(
                            recipeID: recipeID,
                            bindingID: binding.id,
                            moduleID: binding.moduleID
                        )
                    ]
                )
            )

        case let .generatorAsset(generatorID, bindingID):
            guard let generator = workspace.generators.first(where: { $0.id == generatorID }) else {
                return .rejected(.missingGenerator(generatorID))
            }
            guard let binding = generator.assetBindings.first(where: { $0.id == bindingID }) else {
                return .rejected(
                    .missingGeneratorAssetBinding(
                        generatorID: generatorID,
                        bindingID: bindingID
                    )
                )
            }
            return .accepted(
                GraphDisconnectionPlan(
                    operations: [
                        .generatorAssetBinding(
                            generatorID: generatorID,
                            bindingID: binding.id,
                            assetID: binding.assetID
                        )
                    ]
                )
            )

        case .moduleSource, .generatorRecipe, .generationOutput:
            return .rejected(.readOnlyEdge(edgeID))
        }
    }

    public static func decide(
        sourceModuleGroupID groupID: SourceModuleConnectionGroupID,
        moduleIDs requestedModuleIDs: [PromptModuleID],
        in workspace: Workspace
    ) -> GraphDisconnectionDecision {
        let groups = SourceModuleConnectionProjection(workspace: workspace).groups
        guard let group = groups.first(where: { $0.id == groupID }) else {
            return .rejected(.sourceModuleGroupNotFound(groupID))
        }

        let moduleIDs = uniqueIDsPreservingOrder(requestedModuleIDs)
        guard !moduleIDs.isEmpty else {
            return .rejected(.emptySourceModuleSelection(groupID))
        }

        let groupModuleIDs = Set(group.moduleIDs)
        if let invalidModuleID = moduleIDs.first(where: { !groupModuleIDs.contains($0) }) {
            return .rejected(
                .sourceModuleNotInGroup(
                    groupID: groupID,
                    moduleID: invalidModuleID
                )
            )
        }

        guard let generator = workspace.generators.first(
            where: { $0.id == group.generatorID }
        ) else {
            return .rejected(.missingGenerator(group.generatorID))
        }
        guard let recipe = workspace.recipes.first(
            where: { $0.id == generator.recipeID }
        ) else {
            return .rejected(.missingRecipe(generator.recipeID))
        }

        let selectedModuleIDs = Set(moduleIDs)
        let operations: [GraphDisconnectionOperation] = recipe.bindings.compactMap { binding in
            guard selectedModuleIDs.contains(binding.moduleID) else { return nil }
            return GraphDisconnectionOperation.recipeBinding(
                recipeID: recipe.id,
                bindingID: binding.id,
                moduleID: binding.moduleID
            )
        }
        return .accepted(GraphDisconnectionPlan(operations: operations))
    }

    private static func uniqueIDsPreservingOrder(
        _ moduleIDs: [PromptModuleID]
    ) -> [PromptModuleID] {
        var seen: Set<PromptModuleID> = []
        return moduleIDs.filter { seen.insert($0).inserted }
    }
}
