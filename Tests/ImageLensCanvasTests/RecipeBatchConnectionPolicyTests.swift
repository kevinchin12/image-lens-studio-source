import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class RecipeBatchConnectionPolicyTests: XCTestCase {
    func testAcceptedBindingsUseCategoryOrderAndStableRequestOrder() {
        let assetID = AssetID()
        let firstStyle = module(.style, sourceAssetID: assetID, content: "same")
        let subject = module(.subject, sourceAssetID: assetID)
        let composition = module(.composition, sourceAssetID: assetID)
        let secondStyle = module(.style, sourceAssetID: assetID, content: "same")
        let existingStyle = module(.style, sourceAssetID: AssetID())
        let recipe = Recipe(
            name: "Batch",
            bindings: [
                RecipeInputBinding(
                    moduleID: existingStyle.id,
                    role: existingStyle.role,
                    order: 7,
                    priority: .primary
                )
            ],
            target: target
        )

        let plan = RecipeBatchConnectionPolicy.plan(
            recipe: recipe,
            sourceAssetID: assetID,
            candidates: [composition, firstStyle, subject, secondStyle]
        )

        XCTAssertEqual(
            plan.addedModuleIDs,
            [subject.id, firstStyle.id, secondStyle.id, composition.id]
        )
        XCTAssertEqual(plan.addedBindings.map(\.order), [8, 9, 10, 11])
        XCTAssertEqual(
            plan.addedBindings.map(\.priority),
            [.primary, .supporting, .supporting, .primary]
        )
        XCTAssertTrue(plan.skipped.isEmpty)
    }

    func testIDsReportEveryFilterReasonAndDoNotDeduplicateText() {
        let assetID = AssetID()
        let otherAssetID = AssetID()
        let alreadyBound = module(.camera, sourceAssetID: assetID)
        let firstSameText = module(.lighting, sourceAssetID: assetID, content: "soft light")
        let secondSameText = module(.lighting, sourceAssetID: assetID, content: "soft light")
        let mismatched = module(.material, sourceAssetID: otherAssetID)
        let noSource = module(.rendering, sourceAssetID: nil)
        let instruction = PromptModule(
            role: .instruction,
            content: "leave negative space",
            sourceAssetID: assetID,
            evidence: .userProvided
        )
        let missingID = PromptModuleID()
        let recipe = Recipe(
            name: "Filters",
            bindings: [
                RecipeInputBinding(
                    moduleID: alreadyBound.id,
                    role: alreadyBound.role,
                    order: 0,
                    priority: .primary
                )
            ],
            target: target
        )

        let plan = RecipeBatchConnectionPolicy.plan(
            recipe: recipe,
            sourceAssetID: assetID,
            candidateModuleIDs: [
                firstSameText.id,
                missingID,
                mismatched.id,
                noSource.id,
                alreadyBound.id,
                instruction.id,
                firstSameText.id,
                secondSameText.id
            ],
            availableModules: [
                alreadyBound,
                firstSameText,
                secondSameText,
                mismatched,
                noSource,
                instruction
            ]
        )

        XCTAssertEqual(
            plan.addedModuleIDs,
            [firstSameText.id, secondSameText.id]
        )
        XCTAssertEqual(plan.addedBindings.map(\.priority), [.primary, .supporting])
        XCTAssertEqual(
            plan.skipped,
            [
                RecipeBatchConnectionSkip(moduleID: missingID, reason: .missingModule),
                RecipeBatchConnectionSkip(
                    moduleID: mismatched.id,
                    reason: .sourceAssetMismatch(actualSourceAssetID: otherAssetID)
                ),
                RecipeBatchConnectionSkip(
                    moduleID: noSource.id,
                    reason: .sourceAssetMismatch(actualSourceAssetID: nil)
                ),
                RecipeBatchConnectionSkip(moduleID: alreadyBound.id, reason: .alreadyBound),
                RecipeBatchConnectionSkip(moduleID: instruction.id, reason: .unsupportedRole),
                RecipeBatchConnectionSkip(
                    moduleID: firstSameText.id,
                    reason: .duplicateCandidate
                )
            ]
        )
    }

    func testFirstCandidateBecomesPrimaryWhenRoleOnlyHasSupportingBinding() {
        let assetID = AssetID()
        let existing = module(.environment, sourceAssetID: AssetID())
        let first = module(.environment, sourceAssetID: assetID)
        let second = module(.environment, sourceAssetID: assetID)
        let recipe = Recipe(
            name: "Primary Repair",
            bindings: [
                RecipeInputBinding(
                    moduleID: existing.id,
                    role: existing.role,
                    order: 3,
                    priority: .supporting
                )
            ],
            target: target
        )

        let plan = RecipeBatchConnectionPolicy.plan(
            recipe: recipe,
            sourceAssetID: assetID,
            candidates: [first, second]
        )

        XCTAssertEqual(plan.addedBindings.map(\.priority), [.primary, .supporting])
        XCTAssertEqual(plan.addedBindings.map(\.order), [4, 5])
    }

    func testCandidateArrayDeduplicatesByIDBeforePlanning() {
        let assetID = AssetID()
        let candidate = module(.subject, sourceAssetID: assetID)
        let recipe = Recipe(name: "Duplicate", target: target)

        let plan = RecipeBatchConnectionPolicy.plan(
            recipe: recipe,
            sourceAssetID: assetID,
            candidates: [candidate, candidate]
        )

        XCTAssertEqual(plan.addedModuleIDs, [candidate.id])
        XCTAssertEqual(
            plan.skipped,
            [
                RecipeBatchConnectionSkip(
                    moduleID: candidate.id,
                    reason: .duplicateCandidate
                )
            ]
        )
    }

    private var target: CompileTarget {
        CompileTarget(providerID: "test", modelID: "model")
    }

    private func module(
        _ category: PromptModuleCategory,
        sourceAssetID: AssetID?,
        content: String = "prompt"
    ) -> PromptModule {
        PromptModule(
            category: category,
            content: content,
            sourceAssetID: sourceAssetID,
            evidence: .observable
        )
    }
}
