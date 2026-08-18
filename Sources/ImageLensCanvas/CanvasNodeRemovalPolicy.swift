import Foundation
import ImageLensCore

/// Applies the ownership boundary between canvas occurrences and workspace data.
///
/// Images and source-derived prompt modules are reusable workspace content, so
/// removing their canvas nodes never deletes the underlying entities. A
/// source-less prompt module is authored on the canvas; once its final canvas
/// occurrence is removed, the module and its live recipe bindings are removed.
/// A `Generator` is likewise an editable canvas configuration and is removed
/// after its final occurrence. Immutable generation history and compiled prompt
/// snapshots are always kept.
public enum CanvasNodeRemovalPolicy {
    /// Removes legacy grouped-result canvas occurrences while retaining their
    /// generated assets and immutable generation history.
    ///
    /// Only nodes explicitly owned by a result group are retired. Generated
    /// images the user separately placed on the canvas remain untouched.
    @discardableResult
    public static func retireLegacyGenerationResultGroups(
        in workspace: inout Workspace,
        changedAt: Date = .now
    ) -> Bool {
        let memberNodeIDs = Set(workspace.generationGroups.flatMap(\.memberNodeIDs))
        guard !memberNodeIDs.isEmpty || !workspace.generationGroups.isEmpty else { return false }
        workspace.canvasNodes.removeAll { memberNodeIDs.contains($0.id) }
        workspace.generationGroups.removeAll()
        workspace.updatedAt = changedAt
        return true
    }

    /// Removes the requested canvas occurrences and any generator configuration
    /// that no longer has a generation-node occurrence.
    ///
    /// A removed generator's recipe is deleted only when no remaining generator,
    /// generation record, or compiled prompt snapshot refers to it.
    @discardableResult
    public static func remove(
        nodeIDs: Set<CanvasNodeID>,
        from workspace: inout Workspace,
        changedAt: Date = .now
    ) -> CanvasNodeRemovalResult {
        guard !nodeIDs.isEmpty else { return .empty }

        let removedNodes = workspace.canvasNodes.filter { nodeIDs.contains($0.id) }
        guard !removedNodes.isEmpty else { return .empty }

        let candidateGeneratorIDs = Set(
            removedNodes.compactMap { node in
                node.kind == .generation ? node.generatorID : nil
            }
        )
        let candidatePromptModuleIDs = Set(
            removedNodes.compactMap { node in
                node.kind == .module ? node.promptModuleID : nil
            }
        )
        let candidateTextBlockIDs = Set(removedNodes.compactMap(\.textBlockID))
        var candidateRecipeIDs = recipeIDs(
            ownedBy: candidateGeneratorIDs,
            in: workspace
        )
        workspace.canvasNodes.removeAll { nodeIDs.contains($0.id) }

        let promptModuleCleanup = removeSourceLessModulesWithoutOccurrences(
            candidateIDs: candidatePromptModuleIDs,
            from: &workspace,
            changedAt: changedAt
        )
        let removedTextBlockIDs = removeTextBlocksWithoutOccurrences(
            candidateIDs: candidateTextBlockIDs,
            from: &workspace
        )
        candidateRecipeIDs.formUnion(promptModuleCleanup.affectedRecipeIDs)
        let removedGeneratorIDs = removeGeneratorsWithoutOccurrences(
            candidateIDs: candidateGeneratorIDs,
            from: &workspace
        )
        detachGenerationGroups(
            from: removedGeneratorIDs,
            in: &workspace,
            changedAt: changedAt
        )
        let removedRecipeIDs = removeUnreferencedRecipes(
            candidateIDs: candidateRecipeIDs,
            from: &workspace
        )
        workspace.updatedAt = changedAt

        return CanvasNodeRemovalResult(
            removedCanvasNodeIDs: Set(removedNodes.map(\.id)),
            removedPromptModuleIDs: promptModuleCleanup.removedModuleIDs,
            removedTextBlockIDs: removedTextBlockIDs,
            removedGeneratorIDs: removedGeneratorIDs,
            removedRecipeIDs: removedRecipeIDs
        )
    }

    /// Repairs workspaces created under occurrence-only generator deletion.
    ///
    /// Every generator without a generation-node occurrence is pruned. Historical
    /// records and compiled snapshots remain intact and keep their recipes alive.
    @discardableResult
    public static func pruneOrphanedGenerators(
        in workspace: inout Workspace,
        changedAt: Date = .now
    ) -> CanvasNodeRemovalResult {
        let liveGeneratorIDs = Set(
            workspace.canvasNodes.compactMap { node in
                node.kind == .generation ? node.generatorID : nil
            }
        )
        let orphanedGeneratorIDs = Set(workspace.generators.map(\.id))
            .subtracting(liveGeneratorIDs)
        guard !orphanedGeneratorIDs.isEmpty else { return .empty }

        let candidateRecipeIDs = recipeIDs(
            ownedBy: orphanedGeneratorIDs,
            in: workspace
        )
        let removedGeneratorIDs = removeGeneratorsWithoutOccurrences(
            candidateIDs: orphanedGeneratorIDs,
            from: &workspace
        )
        detachGenerationGroups(
            from: removedGeneratorIDs,
            in: &workspace,
            changedAt: changedAt
        )
        let removedRecipeIDs = removeUnreferencedRecipes(
            candidateIDs: candidateRecipeIDs,
            from: &workspace
        )
        workspace.updatedAt = changedAt

        return CanvasNodeRemovalResult(
            removedCanvasNodeIDs: [],
            removedPromptModuleIDs: [],
            removedTextBlockIDs: [],
            removedGeneratorIDs: removedGeneratorIDs,
            removedRecipeIDs: removedRecipeIDs
        )
    }

    /// Repairs source-less prompt modules left by occurrence-only deletion.
    ///
    /// A live canvas occurrence or live recipe binding keeps the module. Frozen
    /// compiled snapshots are immutable history rather than live ownership and
    /// are not edited when an unreachable module is pruned.
    @discardableResult
    public static func pruneOrphanedSourceLessPromptModules(
        in workspace: inout Workspace,
        changedAt: Date = .now
    ) -> CanvasNodeRemovalResult {
        let occurrenceModuleIDs = Set(
            workspace.canvasNodes.compactMap { node in
                node.kind == .module ? node.promptModuleID : nil
            }
        )
        let boundModuleIDs = Set(
            workspace.recipes.flatMap { recipe in
                recipe.bindings.map(\.moduleID)
            }
        )
        let removableIDs = Set<PromptModuleID>(
            workspace.promptModules.compactMap { module in
                guard module.sourceAssetID == nil,
                      !occurrenceModuleIDs.contains(module.id),
                      !boundModuleIDs.contains(module.id) else {
                    return nil
                }
                return module.id
            }
        )
        guard !removableIDs.isEmpty else { return .empty }

        workspace.promptModules.removeAll { removableIDs.contains($0.id) }
        workspace.updatedAt = changedAt
        return CanvasNodeRemovalResult(
            removedCanvasNodeIDs: [],
            removedPromptModuleIDs: removableIDs,
            removedTextBlockIDs: [],
            removedGeneratorIDs: [],
            removedRecipeIDs: []
        )
    }

    private struct PromptModuleCleanupResult {
        let removedModuleIDs: Set<PromptModuleID>
        let affectedRecipeIDs: Set<RecipeID>

        static let empty = PromptModuleCleanupResult(
            removedModuleIDs: [],
            affectedRecipeIDs: []
        )
    }

    private static func removeSourceLessModulesWithoutOccurrences(
        candidateIDs: Set<PromptModuleID>,
        from workspace: inout Workspace,
        changedAt: Date
    ) -> PromptModuleCleanupResult {
        guard !candidateIDs.isEmpty else { return .empty }

        let remainingOccurrenceIDs = Set(
            workspace.canvasNodes.compactMap { node in
                node.kind == .module ? node.promptModuleID : nil
            }
        )
        let removableIDs = Set<PromptModuleID>(
            workspace.promptModules.compactMap { module in
                guard candidateIDs.contains(module.id),
                      module.sourceAssetID == nil,
                      !remainingOccurrenceIDs.contains(module.id) else {
                    return nil
                }
                return module.id
            }
        )
        guard !removableIDs.isEmpty else { return .empty }

        workspace.promptModules.removeAll { removableIDs.contains($0.id) }
        var affectedRecipeIDs: Set<RecipeID> = []
        for recipeIndex in workspace.recipes.indices {
            let originalCount = workspace.recipes[recipeIndex].bindings.count
            workspace.recipes[recipeIndex].bindings.removeAll {
                removableIDs.contains($0.moduleID)
            }
            guard workspace.recipes[recipeIndex].bindings.count != originalCount else {
                continue
            }
            workspace.recipes[recipeIndex].revision += 1
            workspace.recipes[recipeIndex].updatedAt = changedAt
            affectedRecipeIDs.insert(workspace.recipes[recipeIndex].id)
        }
        return PromptModuleCleanupResult(
            removedModuleIDs: removableIDs,
            affectedRecipeIDs: affectedRecipeIDs
        )
    }

    private static func removeGeneratorsWithoutOccurrences(
        candidateIDs: Set<GeneratorID>,
        from workspace: inout Workspace
    ) -> Set<GeneratorID> {
        guard !candidateIDs.isEmpty else { return [] }

        let remainingOccurrenceIDs = Set(
            workspace.canvasNodes.compactMap { node in
                node.kind == .generation ? node.generatorID : nil
            }
        )
        let existingGeneratorIDs = Set(workspace.generators.map(\.id))
        let removableIDs = candidateIDs
            .intersection(existingGeneratorIDs)
            .subtracting(remainingOccurrenceIDs)
        workspace.generators.removeAll { removableIDs.contains($0.id) }
        return removableIDs
    }

    private static func removeTextBlocksWithoutOccurrences(
        candidateIDs: Set<TextBlockID>,
        from workspace: inout Workspace
    ) -> Set<TextBlockID> {
        guard !candidateIDs.isEmpty else { return [] }
        let remainingIDs = Set(workspace.canvasNodes.compactMap(\.textBlockID))
        let removableIDs = candidateIDs.subtracting(remainingIDs)
        workspace.textBlocks.removeAll { removableIDs.contains($0.id) }
        return removableIDs
    }

    private static func detachGenerationGroups(
        from removedGeneratorIDs: Set<GeneratorID>,
        in workspace: inout Workspace,
        changedAt: Date
    ) {
        guard !removedGeneratorIDs.isEmpty else { return }

        for index in workspace.generationGroups.indices {
            guard let generatorID = workspace.generationGroups[index].generatorID,
                  removedGeneratorIDs.contains(generatorID) else {
                continue
            }
            workspace.generationGroups[index].generatorID = nil
            workspace.generationGroups[index].updatedAt = changedAt
        }
    }

    private static func removeUnreferencedRecipes(
        candidateIDs candidateRecipeIDs: Set<RecipeID>,
        from workspace: inout Workspace
    ) -> Set<RecipeID> {
        guard !candidateRecipeIDs.isEmpty else { return [] }

        let referencedRecipeIDs = Set(workspace.generators.map(\.recipeID))
            .union(workspace.generations.map(\.recipeID))
            .union(workspace.compiledPrompts.map(\.recipeID))
            .union(workspace.canvasNodes.compactMap(\.recipeID))
        let removableIDs = candidateRecipeIDs.subtracting(referencedRecipeIDs)
        workspace.recipes.removeAll { removableIDs.contains($0.id) }
        return removableIDs
    }

    private static func recipeIDs(
        ownedBy generatorIDs: Set<GeneratorID>,
        in workspace: Workspace
    ) -> Set<RecipeID> {
        Set(
            workspace.generators.compactMap { generator in
                generatorIDs.contains(generator.id) ? generator.recipeID : nil
            }
        )
    }
}

public struct CanvasNodeRemovalResult: Equatable, Sendable {
    public let removedCanvasNodeIDs: Set<CanvasNodeID>
    public let removedPromptModuleIDs: Set<PromptModuleID>
    public let removedTextBlockIDs: Set<TextBlockID>
    public let removedGeneratorIDs: Set<GeneratorID>
    public let removedRecipeIDs: Set<RecipeID>

    public init(
        removedCanvasNodeIDs: Set<CanvasNodeID>,
        removedPromptModuleIDs: Set<PromptModuleID> = [],
        removedTextBlockIDs: Set<TextBlockID> = [],
        removedGeneratorIDs: Set<GeneratorID>,
        removedRecipeIDs: Set<RecipeID>
    ) {
        self.removedCanvasNodeIDs = removedCanvasNodeIDs
        self.removedPromptModuleIDs = removedPromptModuleIDs
        self.removedTextBlockIDs = removedTextBlockIDs
        self.removedGeneratorIDs = removedGeneratorIDs
        self.removedRecipeIDs = removedRecipeIDs
    }

    public static let empty = CanvasNodeRemovalResult(
        removedCanvasNodeIDs: [],
        removedPromptModuleIDs: [],
        removedTextBlockIDs: [],
        removedGeneratorIDs: [],
        removedRecipeIDs: []
    )

    public var didChange: Bool {
        !removedCanvasNodeIDs.isEmpty
            || !removedPromptModuleIDs.isEmpty
            || !removedTextBlockIDs.isEmpty
            || !removedGeneratorIDs.isEmpty
            || !removedRecipeIDs.isEmpty
    }
}
