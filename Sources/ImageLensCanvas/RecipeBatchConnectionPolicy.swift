import Foundation
import ImageLensCore

/// Explains why a requested prompt module was not included in a batch connection.
public enum RecipeBatchConnectionSkipReason: Equatable, Sendable {
    case duplicateCandidate
    case missingModule
    case sourceAssetMismatch(actualSourceAssetID: AssetID?)
    case alreadyBound
    case unsupportedRole
}

/// A rejected item from a batch connection request.
public struct RecipeBatchConnectionSkip: Equatable, Sendable {
    public let moduleID: PromptModuleID
    public let reason: RecipeBatchConnectionSkipReason

    public init(
        moduleID: PromptModuleID,
        reason: RecipeBatchConnectionSkipReason
    ) {
        self.moduleID = moduleID
        self.reason = reason
    }
}

/// Pure-value result that a caller can apply to a recipe as one undoable change.
public struct RecipeBatchConnectionPlan: Equatable, Sendable {
    public let addedBindings: [RecipeInputBinding]
    public let skipped: [RecipeBatchConnectionSkip]

    public init(
        addedBindings: [RecipeInputBinding],
        skipped: [RecipeBatchConnectionSkip]
    ) {
        self.addedBindings = addedBindings
        self.skipped = skipped
    }

    public var addedModuleIDs: [PromptModuleID] {
        addedBindings.map(\.moduleID)
    }
}

/// Plans a direct structured-prompt connection without mutating workspace state.
///
/// Accepted visual modules are appended in `PromptModuleCategory.allCases`
/// order. Request order remains stable within one category. Identity, rather
/// than prompt text, defines duplicates.
public enum RecipeBatchConnectionPolicy {
    public static func plan(
        recipe: Recipe,
        sourceAssetID: AssetID,
        candidates: [PromptModule]
    ) -> RecipeBatchConnectionPlan {
        let modulesByID = firstModulesByID(candidates)
        return makePlan(
            recipe: recipe,
            sourceAssetID: sourceAssetID,
            candidateModuleIDs: candidates.map(\.id),
            modulesByID: modulesByID
        )
    }

    public static func plan(
        recipe: Recipe,
        sourceAssetID: AssetID,
        candidateModuleIDs: [PromptModuleID],
        availableModules: [PromptModule]
    ) -> RecipeBatchConnectionPlan {
        makePlan(
            recipe: recipe,
            sourceAssetID: sourceAssetID,
            candidateModuleIDs: candidateModuleIDs,
            modulesByID: firstModulesByID(availableModules)
        )
    }

    private static func makePlan(
        recipe: Recipe,
        sourceAssetID: AssetID,
        candidateModuleIDs: [PromptModuleID],
        modulesByID: [PromptModuleID: PromptModule]
    ) -> RecipeBatchConnectionPlan {
        let alreadyBoundModuleIDs = Set(recipe.bindings.map(\.moduleID))
        var seenCandidateIDs: Set<PromptModuleID> = []
        var accepted: [(requestOffset: Int, module: PromptModule)] = []
        var skipped: [RecipeBatchConnectionSkip] = []

        for (requestOffset, moduleID) in candidateModuleIDs.enumerated() {
            guard seenCandidateIDs.insert(moduleID).inserted else {
                skipped.append(
                    RecipeBatchConnectionSkip(
                        moduleID: moduleID,
                        reason: .duplicateCandidate
                    )
                )
                continue
            }
            guard let module = modulesByID[moduleID] else {
                skipped.append(
                    RecipeBatchConnectionSkip(
                        moduleID: moduleID,
                        reason: .missingModule
                    )
                )
                continue
            }
            guard module.sourceAssetID == sourceAssetID else {
                skipped.append(
                    RecipeBatchConnectionSkip(
                        moduleID: moduleID,
                        reason: .sourceAssetMismatch(
                            actualSourceAssetID: module.sourceAssetID
                        )
                    )
                )
                continue
            }
            guard module.category != nil else {
                skipped.append(
                    RecipeBatchConnectionSkip(
                        moduleID: moduleID,
                        reason: .unsupportedRole
                    )
                )
                continue
            }
            guard !alreadyBoundModuleIDs.contains(moduleID) else {
                skipped.append(
                    RecipeBatchConnectionSkip(
                        moduleID: moduleID,
                        reason: .alreadyBound
                    )
                )
                continue
            }
            accepted.append((requestOffset, module))
        }

        let categoryOrder = Dictionary(
            uniqueKeysWithValues: PromptModuleCategory.allCases.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        accepted.sort { lhs, rhs in
            let lhsCategory = lhs.module.category!
            let rhsCategory = rhs.module.category!
            let lhsRank = categoryOrder[lhsCategory]!
            let rhsRank = categoryOrder[rhsCategory]!
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.requestOffset < rhs.requestOffset
        }

        var rolesWithPrimary = Set(
            recipe.bindings.lazy
                .filter { $0.priority == .primary }
                .map(\.role)
        )
        var nextOrder = (recipe.bindings.map(\.order).max() ?? -1) + 1
        let addedBindings = accepted.map { item in
            let module = item.module
            let priority: RecipeBindingPriority
            if rolesWithPrimary.contains(module.role) {
                priority = .supporting
            } else {
                priority = .primary
                rolesWithPrimary.insert(module.role)
            }
            defer { nextOrder += 1 }
            return RecipeInputBinding(
                moduleID: module.id,
                role: module.role,
                order: nextOrder,
                priority: priority
            )
        }

        return RecipeBatchConnectionPlan(
            addedBindings: addedBindings,
            skipped: skipped
        )
    }

    private static func firstModulesByID(
        _ modules: [PromptModule]
    ) -> [PromptModuleID: PromptModule] {
        var result: [PromptModuleID: PromptModule] = [:]
        for module in modules where result[module.id] == nil {
            result[module.id] = module
        }
        return result
    }
}
