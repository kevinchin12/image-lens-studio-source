import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensCanvas

final class SourceModuleConnectionProjectionTests: XCTestCase {
    func testGroupsUnmaterializedModulesByAssetAndGenerator() {
        let firstAssetID = AssetID()
        let secondAssetID = AssetID()
        let firstModule = module(.subject, sourceAssetID: firstAssetID)
        let materializedModule = module(.style, sourceAssetID: firstAssetID)
        let secondModule = module(.camera, sourceAssetID: secondAssetID)
        let freehandModule = module(.composition, sourceAssetID: nil)
        let recipe = Recipe(
            name: "Projection",
            bindings: [
                binding(secondModule, order: 3),
                binding(materializedModule, order: 1),
                binding(firstModule, order: 0),
                binding(freehandModule, order: 2)
            ],
            target: target
        )
        let generator = Generator(
            name: "Generator",
            recipeID: recipe.id,
            target: target
        )
        let materializedNode = CanvasNode(
            promptModuleID: materializedModule.id,
            frame: WorldRect(x: 0, y: 0, width: 100, height: 100)
        )
        let workspace = Workspace(
            title: "Projection",
            promptModules: [
                firstModule,
                materializedModule,
                secondModule,
                freehandModule
            ],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [materializedNode]
        )

        let projection = SourceModuleConnectionProjection(workspace: workspace)

        XCTAssertEqual(
            projection.groups,
            [
                SourceModuleConnectionGroup(
                    assetID: firstAssetID,
                    generatorID: generator.id,
                    moduleIDs: [firstModule.id]
                ),
                SourceModuleConnectionGroup(
                    assetID: secondAssetID,
                    generatorID: generator.id,
                    moduleIDs: [secondModule.id]
                )
            ]
        )
        XCTAssertEqual(projection.groups.map(\.count), [1, 1])
    }

    func testSameSourceProducesIndependentGroupsForEachGenerator() {
        let assetID = AssetID()
        let firstModule = module(.lighting, sourceAssetID: assetID)
        let secondModule = module(.material, sourceAssetID: assetID)
        let firstRecipe = Recipe(
            name: "First",
            bindings: [binding(firstModule, order: 0)],
            target: target
        )
        let secondRecipe = Recipe(
            name: "Second",
            bindings: [
                binding(firstModule, order: 0),
                binding(secondModule, order: 1)
            ],
            target: target
        )
        let firstGenerator = Generator(
            name: "First",
            recipeID: firstRecipe.id,
            target: target
        )
        let secondGenerator = Generator(
            name: "Second",
            recipeID: secondRecipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Pairs",
            promptModules: [firstModule, secondModule],
            recipes: [firstRecipe, secondRecipe],
            generators: [firstGenerator, secondGenerator]
        )

        let groups = SourceModuleConnectionProjection(workspace: workspace).groups

        XCTAssertEqual(groups.map(\.id), [
            SourceModuleConnectionGroupID(
                assetID: assetID,
                generatorID: firstGenerator.id
            ),
            SourceModuleConnectionGroupID(
                assetID: assetID,
                generatorID: secondGenerator.id
            )
        ])
        XCTAssertEqual(groups.map(\.count), [1, 2])
    }

    func testDuplicateBindingsCountModuleOnceAndIgnoreMissingEntities() {
        let assetID = AssetID()
        let sourceModule = module(.rendering, sourceAssetID: assetID)
        let missingModuleID = PromptModuleID()
        let recipe = Recipe(
            name: "Malformed",
            bindings: [
                binding(sourceModule, order: 1),
                binding(sourceModule, order: 0),
                RecipeInputBinding(
                    moduleID: missingModuleID,
                    role: .visual(.style),
                    order: 2
                )
            ],
            target: target
        )
        let generator = Generator(
            name: "Generator",
            recipeID: recipe.id,
            target: target
        )
        let unrelatedImageNode = CanvasNode(
            kind: .image,
            entityID: sourceModule.id.rawValue,
            frame: WorldRect(x: 0, y: 0, width: 100, height: 100)
        )
        let workspace = Workspace(
            title: "Malformed",
            promptModules: [sourceModule],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [unrelatedImageNode]
        )

        let groups = SourceModuleConnectionProjection(workspace: workspace).groups

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.moduleIDs, [sourceModule.id])
        XCTAssertEqual(groups.first?.count, 1)
    }

    func testAnyModuleCanvasOccurrenceRemovesItFromAggregation() {
        let assetID = AssetID()
        let sourceModule = module(.environment, sourceAssetID: assetID)
        let recipe = Recipe(
            name: "Materialized",
            bindings: [binding(sourceModule, order: 0)],
            target: target
        )
        let generator = Generator(
            name: "Generator",
            recipeID: recipe.id,
            target: target
        )
        let firstNode = CanvasNode(
            promptModuleID: sourceModule.id,
            frame: WorldRect(x: 0, y: 0, width: 100, height: 100)
        )
        let secondNode = CanvasNode(
            promptModuleID: sourceModule.id,
            frame: WorldRect(x: 200, y: 0, width: 100, height: 100)
        )
        let workspace = Workspace(
            title: "Materialized",
            promptModules: [sourceModule],
            recipes: [recipe],
            generators: [generator],
            canvasNodes: [firstNode, secondNode]
        )

        XCTAssertTrue(
            SourceModuleConnectionProjection(workspace: workspace).groups.isEmpty
        )
    }

    func testDisabledBindingIsNotProjectedAsAnActiveConnection() {
        let assetID = AssetID()
        let enabledModule = module(.subject, sourceAssetID: assetID)
        let disabledModule = module(.style, sourceAssetID: assetID)
        let recipe = Recipe(
            name: "Enabled State",
            bindings: [
                binding(enabledModule, order: 0),
                RecipeInputBinding(
                    moduleID: disabledModule.id,
                    role: disabledModule.role,
                    order: 1,
                    isEnabled: false
                )
            ],
            target: target
        )
        let generator = Generator(
            name: "Generator",
            recipeID: recipe.id,
            target: target
        )
        let workspace = Workspace(
            title: "Enabled State",
            promptModules: [enabledModule, disabledModule],
            recipes: [recipe],
            generators: [generator]
        )

        let groups = SourceModuleConnectionProjection(workspace: workspace).groups

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.moduleIDs, [enabledModule.id])
    }

    private var target: CompileTarget {
        CompileTarget(providerID: "test", modelID: "model")
    }

    private func module(
        _ category: PromptModuleCategory,
        sourceAssetID: AssetID?
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
