import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class GraphDisconnectionPolicyTests: XCTestCase {
    func testRecipeEdgeResolvesOnlyItsStableBindingID() {
        let module = promptModule(.subject)
        let firstBinding = RecipeInputBinding(
            moduleID: module.id,
            role: module.role,
            order: 0
        )
        let siblingBinding = RecipeInputBinding(
            moduleID: module.id,
            role: module.role,
            order: 1
        )
        let recipe = Recipe(
            name: "Exact",
            bindings: [firstBinding, siblingBinding],
            target: target
        )
        let workspace = Workspace(
            title: "Exact",
            promptModules: [module],
            recipes: [recipe]
        )

        let decision = GraphDisconnectionPolicy.decide(
            edgeID: .recipeBinding(
                recipeID: recipe.id,
                bindingID: firstBinding.id
            ),
            in: workspace
        )

        XCTAssertEqual(
            decision,
            .accepted(
                GraphDisconnectionPlan(
                    operations: [
                        .recipeBinding(
                            recipeID: recipe.id,
                            bindingID: firstBinding.id,
                            moduleID: module.id
                        )
                    ]
                )
            )
        )
        XCTAssertFalse(
            decision.plan?.edgeIDs.contains(
                .recipeBinding(
                    recipeID: recipe.id,
                    bindingID: siblingBinding.id
                )
            ) ?? true
        )
    }

    func testReferenceAssetEdgeResolvesOnlyItsStableBindingID() {
        let assetID = AssetID()
        let selected = GeneratorAssetBinding(
            assetID: assetID,
            role: .style,
            order: 0
        )
        let sibling = GeneratorAssetBinding(
            assetID: assetID,
            role: .composition,
            order: 1
        )
        let recipe = Recipe(name: "Assets", target: target)
        let generator = Generator(
            name: "Assets",
            recipeID: recipe.id,
            target: target,
            assetBindings: [selected, sibling]
        )
        let workspace = Workspace(
            title: "Assets",
            recipes: [recipe],
            generators: [generator]
        )

        let decision = GraphDisconnectionPolicy.decide(
            edgeID: .generatorAsset(
                generatorID: generator.id,
                bindingID: selected.id
            ),
            in: workspace
        )

        XCTAssertEqual(
            decision,
            .accepted(
                GraphDisconnectionPlan(
                    operations: [
                        .generatorAssetBinding(
                            generatorID: generator.id,
                            bindingID: selected.id,
                            assetID: assetID
                        )
                    ]
                )
            )
        )
        XCTAssertFalse(
            decision.plan?.edgeIDs.contains(
                .generatorAsset(
                    generatorID: generator.id,
                    bindingID: sibling.id
                )
            ) ?? true
        )
    }

    func testReferenceAssetPlanAppliesExactlyAndRevisesGeneratorOnce() throws {
        let timestamp = Date(timeIntervalSince1970: 2_345)
        let assetID = AssetID()
        let selected = GeneratorAssetBinding(
            assetID: assetID,
            role: .style,
            order: 0
        )
        let sibling = GeneratorAssetBinding(
            assetID: assetID,
            role: .composition,
            order: 1
        )
        let recipe = Recipe(name: "Asset Apply", target: target)
        let generator = Generator(
            name: "Asset Apply",
            recipeID: recipe.id,
            target: target,
            assetBindings: [selected, sibling],
            revision: 7
        )
        var workspace = Workspace(
            title: "Asset Apply",
            recipes: [recipe],
            generators: [generator]
        )
        let plan = try XCTUnwrap(
            GraphDisconnectionPolicy.decide(
                edgeID: .generatorAsset(
                    generatorID: generator.id,
                    bindingID: selected.id
                ),
                in: workspace
            ).plan
        )

        let application = plan.apply(to: &workspace, updatedAt: timestamp)

        XCTAssertEqual(application.affectedGeneratorIDs, [generator.id])
        XCTAssertEqual(workspace.generators[0].assetBindings, [sibling])
        XCTAssertEqual(workspace.generators[0].revision, 8)
        XCTAssertEqual(workspace.generators[0].updatedAt, timestamp)
    }

    func testAggregateRemovesAllBindingsForOnlySelectedModuleIDs() {
        let assetID = AssetID()
        let subject = promptModule(.subject, sourceAssetID: assetID)
        let style = promptModule(.style, sourceAssetID: assetID)
        let lighting = promptModule(.lighting, sourceAssetID: assetID)
        let subjectPrimary = binding(subject, order: 0)
        let untouchedStyle = binding(style, order: 1)
        let selectedLighting = binding(lighting, order: 2)
        let duplicateSubject = binding(subject, order: 3)
        let recipe = Recipe(
            name: "Aggregate",
            bindings: [
                subjectPrimary,
                untouchedStyle,
                selectedLighting,
                duplicateSubject
            ],
            target: target
        )
        let generator = Generator(
            name: "Aggregate",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Aggregate",
            promptModules: [subject, style, lighting],
            recipes: [recipe],
            generators: [generator]
        )
        let groupID = SourceModuleConnectionGroupID(
            assetID: assetID,
            generatorID: generator.id
        )

        let decision = GraphDisconnectionPolicy.decide(
            sourceModuleGroupID: groupID,
            moduleIDs: [lighting.id, subject.id, lighting.id],
            in: workspace
        )

        XCTAssertEqual(
            decision.plan?.operations,
            [
                .recipeBinding(
                    recipeID: recipe.id,
                    bindingID: subjectPrimary.id,
                    moduleID: subject.id
                ),
                .recipeBinding(
                    recipeID: recipe.id,
                    bindingID: selectedLighting.id,
                    moduleID: lighting.id
                ),
                .recipeBinding(
                    recipeID: recipe.id,
                    bindingID: duplicateSubject.id,
                    moduleID: subject.id
                )
            ]
        )
        XCTAssertFalse(
            decision.plan?.edgeIDs.contains(
                .recipeBinding(
                    recipeID: recipe.id,
                    bindingID: untouchedStyle.id
                )
            ) ?? true
        )
    }

    func testAggregatePlanAppliesAsOneRecipeRevisionAndPreservesSiblings() throws {
        let timestamp = Date(timeIntervalSince1970: 1_234)
        let assetID = AssetID()
        let first = promptModule(.subject, sourceAssetID: assetID)
        let sibling = promptModule(.style, sourceAssetID: assetID)
        let third = promptModule(.lighting, sourceAssetID: assetID)
        let firstBinding = binding(first, order: 0)
        let siblingBinding = binding(sibling, order: 1)
        let thirdBinding = binding(third, order: 2)
        let recipe = Recipe(
            name: "Apply",
            bindings: [firstBinding, siblingBinding, thirdBinding],
            target: target,
            revision: 4
        )
        let generator = Generator(
            name: "Apply",
            recipeID: recipe.id,
            target: target
        )
        var workspace = Workspace(
            title: "Apply",
            promptModules: [first, sibling, third],
            recipes: [recipe],
            generators: [generator]
        )
        let groupID = SourceModuleConnectionGroupID(
            assetID: assetID,
            generatorID: generator.id
        )
        let decision = GraphDisconnectionPolicy.decide(
            sourceModuleGroupID: groupID,
            moduleIDs: [first.id, third.id],
            in: workspace
        )
        let plan = try XCTUnwrap(decision.plan)

        let application = plan.apply(to: &workspace, updatedAt: timestamp)

        XCTAssertEqual(application.affectedRecipeIDs, [recipe.id])
        XCTAssertTrue(application.affectedGeneratorIDs.isEmpty)
        XCTAssertEqual(
            workspace.recipes[0].bindings.map(\.id),
            [siblingBinding.id]
        )
        XCTAssertEqual(workspace.recipes[0].revision, 5)
        XCTAssertEqual(workspace.recipes[0].updatedAt, timestamp)
        XCTAssertEqual(workspace.updatedAt, timestamp)
    }

    func testStalePlanDoesNotRemoveReplacementBindingOrReviseWorkspace() {
        let module = promptModule(.subject)
        let oldBinding = binding(module, order: 0)
        let recipe = Recipe(
            name: "Stale",
            bindings: [oldBinding],
            target: target,
            revision: 2
        )
        let originalWorkspaceDate = Date(timeIntervalSince1970: 10)
        var workspace = Workspace(
            title: "Stale",
            promptModules: [module],
            recipes: [recipe],
            updatedAt: originalWorkspaceDate
        )
        let plan = GraphDisconnectionPolicy.decide(
            edgeID: .recipeBinding(
                recipeID: recipe.id,
                bindingID: oldBinding.id
            ),
            in: workspace
        ).plan!
        let replacement = RecipeInputBinding(
            id: oldBinding.id,
            moduleID: PromptModuleID(),
            role: .visual(.style),
            order: 0
        )
        workspace.recipes[0].bindings = [replacement]

        let application = plan.apply(
            to: &workspace,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertFalse(application.didChange)
        XCTAssertEqual(workspace.recipes[0].bindings, [replacement])
        XCTAssertEqual(workspace.recipes[0].revision, 2)
        XCTAssertEqual(workspace.updatedAt, originalWorkspaceDate)
    }

    func testAggregateRejectsForeignModuleWithoutPartiallyPlanning() {
        let assetID = AssetID()
        let connected = promptModule(.subject, sourceAssetID: assetID)
        let foreign = promptModule(.style, sourceAssetID: AssetID())
        let recipe = Recipe(
            name: "Atomic",
            bindings: [binding(connected, order: 0)],
            target: target
        )
        let generator = Generator(
            name: "Atomic",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Atomic",
            promptModules: [connected, foreign],
            recipes: [recipe],
            generators: [generator]
        )
        let groupID = SourceModuleConnectionGroupID(
            assetID: assetID,
            generatorID: generator.id
        )

        let decision = GraphDisconnectionPolicy.decide(
            sourceModuleGroupID: groupID,
            moduleIDs: [connected.id, foreign.id],
            in: workspace
        )

        XCTAssertEqual(
            decision,
            .rejected(
                .sourceModuleNotInGroup(
                    groupID: groupID,
                    moduleID: foreign.id
                )
            )
        )
        XCTAssertNil(decision.plan)
    }

    func testEveryLineageAndStructuralEdgeIsRejectedAsReadOnly() {
        let moduleSource = GraphEdgeID.moduleSource(
            moduleID: PromptModuleID(),
            assetID: AssetID()
        )
        let generatorRecipe = GraphEdgeID.generatorRecipe(
            generatorID: GeneratorID(),
            recipeID: RecipeID()
        )
        let generationOutput = GraphEdgeID.generationOutput(
            generationID: GenerationID(),
            assetID: AssetID()
        )
        let workspace = Workspace(title: "Read-only")

        for edgeID in [moduleSource, generatorRecipe, generationOutput] {
            XCTAssertEqual(
                GraphDisconnectionPolicy.decide(
                    .edge(edgeID),
                    in: workspace
                ),
                .rejected(.readOnlyEdge(edgeID))
            )
        }
    }

    func testMissingStableBindingsAreRejected() {
        let recipe = Recipe(name: "Missing", target: target)
        let generator = Generator(
            name: "Missing",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Missing",
            recipes: [recipe],
            generators: [generator]
        )
        let missingRecipeBindingID = RecipeBindingID()
        let missingAssetBindingID = GeneratorAssetBindingID()

        XCTAssertEqual(
            GraphDisconnectionPolicy.decide(
                edgeID: .recipeBinding(
                    recipeID: recipe.id,
                    bindingID: missingRecipeBindingID
                ),
                in: workspace
            ),
            .rejected(
                .missingRecipeBinding(
                    recipeID: recipe.id,
                    bindingID: missingRecipeBindingID
                )
            )
        )
        XCTAssertEqual(
            GraphDisconnectionPolicy.decide(
                edgeID: .generatorAsset(
                    generatorID: generator.id,
                    bindingID: missingAssetBindingID
                ),
                in: workspace
            ),
            .rejected(
                .missingGeneratorAssetBinding(
                    generatorID: generator.id,
                    bindingID: missingAssetBindingID
                )
            )
        )
    }

    private var target: CompileTarget {
        CompileTarget(providerID: "test", modelID: "model")
    }

    private func promptModule(
        _ category: PromptModuleCategory,
        sourceAssetID: AssetID? = nil
    ) -> PromptModule {
        PromptModule(
            category: category,
            content: category.rawValue,
            sourceAssetID: sourceAssetID,
            evidence: .observable
        )
    }

    private func binding(
        _ module: PromptModule,
        order: Int
    ) -> RecipeInputBinding {
        RecipeInputBinding(
            moduleID: module.id,
            role: module.role,
            order: order
        )
    }
}
