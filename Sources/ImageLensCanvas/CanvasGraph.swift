import Foundation
import ImageLensCore

/// A semantic graph owner. These references point at domain entities rather
/// than canvas placements, so moving or temporarily hiding a node cannot alter
/// the recipe or generation graph.
public enum GraphEntityReference: Hashable, Sendable {
    case asset(AssetID)
    case module(PromptModuleID)
    case textBlock(TextBlockID)
    case recipe(RecipeID)
    case generator(GeneratorID)
    case generationRun(GenerationID)

    public init?(node: CanvasNode, workspace: Workspace) {
        switch node.kind {
        case .image:
            guard let id = node.imageAssetID else { return nil }
            self = .asset(id)
        case .module:
            guard let id = node.promptModuleID else { return nil }
            self = .module(id)
        case .text:
            guard let id = node.textBlockID else { return nil }
            self = .textBlock(id)
        case .recipe:
            guard let id = node.recipeID else { return nil }
            self = .recipe(id)
        case .generation:
            guard let rawID = node.generatorID else { return nil }
            if workspace.generators.contains(where: { $0.id == rawID }) {
                self = .generator(rawID)
            } else {
                let generationID = GenerationID(node.entityID)
                guard workspace.generations.contains(where: { $0.id == generationID }) else {
                    return nil
                }
                self = .generationRun(generationID)
            }
        }
    }
}

public enum GraphPortDirection: Hashable, Sendable {
    case input
    case output
}

/// The complete MVP value vocabulary. There is intentionally no `any` case.
public enum GraphPortValueType: Hashable, Sendable {
    case imageAsset
    case videoAsset
    case mediaAsset
    case promptModule(PromptModuleRole)
    case compiledPrompt
}

public enum GraphPortCardinality: Hashable, Sendable {
    case one
    case many
}

/// Stable, typed port roles used to derive port IDs and draw node chrome.
public enum GraphGeneratorAssetPortRole: String, CaseIterable, Hashable, Sendable {
    case general
    case identity
    case environment
    case style
    case composition
    case palette
    case structure

    public init(_ role: GeneratorAssetRole) {
        switch role {
        case .general: self = .general
        case .identity: self = .identity
        case .environment: self = .environment
        case .style: self = .style
        case .composition: self = .composition
        case .palette: self = .palette
        case .structure: self = .structure
        }
    }
}

public enum GraphPortKey: Hashable, Sendable {
    case assetOutput
    case assetGenerationInput
    case moduleSourceInput
    case moduleOutput(PromptModuleRole)
    case recipeInput(PromptModuleRole)
    case recipeOutput
    case generatorRecipeInput
    case generatorAssetInput(GraphGeneratorAssetPortRole)
    case generatorOutput
}

public struct GraphPortID: Hashable, Sendable {
    public var owner: GraphEntityReference
    public var key: GraphPortKey

    public init(owner: GraphEntityReference, key: GraphPortKey) {
        self.owner = owner
        self.key = key
    }
}

public struct GraphPortProjection: Hashable, Identifiable, Sendable {
    public var id: GraphPortID
    public var direction: GraphPortDirection
    public var valueType: GraphPortValueType
    public var cardinality: GraphPortCardinality

    public init(
        id: GraphPortID,
        direction: GraphPortDirection,
        valueType: GraphPortValueType,
        cardinality: GraphPortCardinality
    ) {
        self.id = id
        self.direction = direction
        self.valueType = valueType
        self.cardinality = cardinality
    }

    public static func assetOutput(_ assetID: AssetID) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: .asset(assetID), key: .assetOutput),
            direction: .output,
            valueType: .imageAsset,
            cardinality: .many
        )
    }

    public static func assetOutput(_ asset: Asset) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: .asset(asset.id), key: .assetOutput),
            direction: .output,
            valueType: asset.isVideo ? .videoAsset : .imageAsset,
            cardinality: .many
        )
    }

    public static func assetGenerationInput(_ assetID: AssetID) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: .asset(assetID), key: .assetGenerationInput),
            direction: .input,
            valueType: .imageAsset,
            cardinality: .one
        )
    }

    public static func moduleSourceInput(_ moduleID: PromptModuleID) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: .module(moduleID), key: .moduleSourceInput),
            direction: .input,
            valueType: .imageAsset,
            cardinality: .one
        )
    }

    public static func moduleOutput(_ module: PromptModule) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: .module(module.id), key: .moduleOutput(module.role)),
            direction: .output,
            valueType: .promptModule(module.role),
            cardinality: .many
        )
    }

    public static func recipeInput(
        _ recipeID: RecipeID,
        role: PromptModuleRole
    ) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: .recipe(recipeID), key: .recipeInput(role)),
            direction: .input,
            valueType: .promptModule(role),
            cardinality: .many
        )
    }

    public static func recipeOutput(_ recipeID: RecipeID) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: .recipe(recipeID), key: .recipeOutput),
            direction: .output,
            valueType: .compiledPrompt,
            cardinality: .many
        )
    }

    public static func generatorRecipeInput(_ generatorID: GeneratorID) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: .generator(generatorID), key: .generatorRecipeInput),
            direction: .input,
            valueType: .compiledPrompt,
            cardinality: .one
        )
    }

    public static func generatorAssetInput(
        _ generatorID: GeneratorID,
        role: GeneratorAssetRole
    ) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(
                owner: .generator(generatorID),
                key: .generatorAssetInput(GraphGeneratorAssetPortRole(role))
            ),
            direction: .input,
            valueType: .mediaAsset,
            cardinality: .many
        )
    }

    public static func generatorOutput(_ generatorID: GeneratorID) -> GraphPortProjection {
        generatorOutput(owner: .generator(generatorID))
    }

    public static func generationRunOutput(_ generationID: GenerationID) -> GraphPortProjection {
        generatorOutput(owner: .generationRun(generationID))
    }

    private static func generatorOutput(owner: GraphEntityReference) -> GraphPortProjection {
        GraphPortProjection(
            id: GraphPortID(owner: owner, key: .generatorOutput),
            direction: .output,
            valueType: .imageAsset,
            cardinality: .many
        )
    }
}

public enum GraphDependencyRole: Hashable, Sendable {
    case recipeBinding(RecipeBindingID)
    case generatorRecipe
    case generatorAsset(GeneratorAssetBindingID)
}

public enum GraphLineageRole: Hashable, Sendable {
    case moduleSource
    case generationOutput(GenerationID)
}

public enum GraphEdgeRole: Hashable, Sendable {
    case dependency(GraphDependencyRole)
    case lineage(GraphLineageRole)
}

public enum GraphEdgeID: Hashable, Sendable {
    case moduleSource(moduleID: PromptModuleID, assetID: AssetID)
    case recipeBinding(recipeID: RecipeID, bindingID: RecipeBindingID)
    case generatorRecipe(generatorID: GeneratorID, recipeID: RecipeID)
    case generatorAsset(generatorID: GeneratorID, bindingID: GeneratorAssetBindingID)
    case generationOutput(generationID: GenerationID, assetID: AssetID)
}

/// An edge derived from domain references. It is never stored back into the
/// workspace, preventing a second graph-shaped source of truth.
public struct GraphEdgeProjection: Hashable, Identifiable, Sendable {
    public var id: GraphEdgeID
    public var source: GraphPortProjection
    public var target: GraphPortProjection
    public var role: GraphEdgeRole
    public var isEditable: Bool

    public init(
        id: GraphEdgeID,
        source: GraphPortProjection,
        target: GraphPortProjection,
        role: GraphEdgeRole,
        isEditable: Bool
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.role = role
        self.isEditable = isEditable
    }
}

public enum ConnectionValidationIssue: Equatable, Sendable {
    case sourceMustBeOutput
    case targetMustBeInput
    case incompatibleValue(source: GraphPortValueType, target: GraphPortValueType)
    case duplicateBinding
    case cardinalityExceeded(GraphPortID)
}

public struct ConnectionValidationResult: Equatable, Sendable {
    public var issues: [ConnectionValidationIssue]

    public init(issues: [ConnectionValidationIssue]) {
        self.issues = issues
    }

    public var isValid: Bool { issues.isEmpty }
}

/// Validates a proposed typed connection against already-derived graph edges.
public struct ConnectionValidator: Sendable {
    public init() {}

    public func validate(
        source: GraphPortProjection,
        target: GraphPortProjection,
        existingEdges: some Sequence<GraphEdgeProjection> = []
    ) -> ConnectionValidationResult {
        var issues: [ConnectionValidationIssue] = []
        let edges = Array(existingEdges)

        if source.direction != .output {
            issues.append(.sourceMustBeOutput)
        }
        if target.direction != .input {
            issues.append(.targetMustBeInput)
        }
        if !Self.valuesAreCompatible(source: source.valueType, target: target.valueType) {
            issues.append(.incompatibleValue(source: source.valueType, target: target.valueType))
        }
        if edges.contains(where: { $0.source.id == source.id && $0.target.id == target.id }) {
            issues.append(.duplicateBinding)
        }
        if source.cardinality == .one && edges.contains(where: { $0.source.id == source.id }) {
            issues.append(.cardinalityExceeded(source.id))
        }
        if target.cardinality == .one && edges.contains(where: { $0.target.id == target.id }) {
            issues.append(.cardinalityExceeded(target.id))
        }

        return ConnectionValidationResult(issues: issues)
    }

    private static func valuesAreCompatible(
        source: GraphPortValueType,
        target: GraphPortValueType
    ) -> Bool {
        if source == target { return true }
        switch (source, target) {
        case (.imageAsset, .mediaAsset), (.videoAsset, .mediaAsset):
            return true
        default:
            return false
        }
    }
}

/// Pure-value projection of the persisted workspace graph.
public struct GraphProjection: Equatable, Sendable {
    public var ports: [GraphPortProjection]
    public var edges: [GraphEdgeProjection]

    public init(workspace: Workspace) {
        ports = Self.makePorts(workspace: workspace)
        edges = Self.makeEdges(workspace: workspace)
    }

    public func port(id: GraphPortID) -> GraphPortProjection? {
        ports.first { $0.id == id }
    }

    public func ports(for owner: GraphEntityReference) -> [GraphPortProjection] {
        ports.filter { $0.id.owner == owner }
    }

    private static func makePorts(workspace: Workspace) -> [GraphPortProjection] {
        var result: [GraphPortProjection] = []

        for asset in workspace.assets {
            result.append(.assetOutput(asset))
            result.append(.assetGenerationInput(asset.id))
        }
        for module in workspace.promptModules {
            result.append(.moduleSourceInput(module.id))
            result.append(.moduleOutput(module))
        }
        for recipe in workspace.recipes {
            for category in PromptModuleCategory.allCases {
                result.append(.recipeInput(recipe.id, role: .visual(category)))
            }
            result.append(.recipeInput(recipe.id, role: .instruction))
            result.append(.recipeOutput(recipe.id))
        }
        for generator in workspace.generators {
            result.append(.generatorRecipeInput(generator.id))
            for role in GeneratorAssetRole.allCases {
                result.append(.generatorAssetInput(generator.id, role: role))
            }
            result.append(.generatorOutput(generator.id))
        }
        for generation in workspace.generations where generation.generatorID == nil {
            result.append(.generationRunOutput(generation.id))
        }
        return result
    }

    private static func makeEdges(workspace: Workspace) -> [GraphEdgeProjection] {
        var modulesByID: [PromptModuleID: PromptModule] = [:]
        for module in workspace.promptModules {
            modulesByID[module.id] = module
        }
        var result: [GraphEdgeProjection] = []
        let assetsByID = Dictionary(uniqueKeysWithValues: workspace.assets.map { ($0.id, $0) })

        for module in workspace.promptModules {
            guard let assetID = module.sourceAssetID else { continue }
            result.append(
                GraphEdgeProjection(
                    id: .moduleSource(moduleID: module.id, assetID: assetID),
                    source: assetsByID[assetID].map(GraphPortProjection.assetOutput)
                        ?? .assetOutput(assetID),
                    target: .moduleSourceInput(module.id),
                    role: .lineage(.moduleSource),
                    isEditable: false
                )
            )
        }

        for recipe in workspace.recipes {
            for binding in recipe.bindings {
                let source: GraphPortProjection
                if let module = modulesByID[binding.moduleID] {
                    source = .moduleOutput(module)
                } else {
                    source = GraphPortProjection(
                        id: GraphPortID(
                            owner: .module(binding.moduleID),
                            key: .moduleOutput(binding.role)
                        ),
                        direction: .output,
                        valueType: .promptModule(binding.role),
                        cardinality: .many
                    )
                }
                result.append(
                    GraphEdgeProjection(
                        id: .recipeBinding(recipeID: recipe.id, bindingID: binding.id),
                        source: source,
                        target: .recipeInput(recipe.id, role: binding.role),
                        role: .dependency(.recipeBinding(binding.id)),
                        isEditable: true
                    )
                )
            }
        }

        for generator in workspace.generators {
            result.append(
                GraphEdgeProjection(
                    id: .generatorRecipe(generatorID: generator.id, recipeID: generator.recipeID),
                    source: .recipeOutput(generator.recipeID),
                    target: .generatorRecipeInput(generator.id),
                    role: .dependency(.generatorRecipe),
                    isEditable: false
                )
            )
            for binding in generator.assetBindings {
                result.append(
                    GraphEdgeProjection(
                        id: .generatorAsset(generatorID: generator.id, bindingID: binding.id),
                    source: assetsByID[binding.assetID].map(GraphPortProjection.assetOutput)
                        ?? .assetOutput(binding.assetID),
                        target: .generatorAssetInput(generator.id, role: binding.role),
                        role: .dependency(.generatorAsset(binding.id)),
                        isEditable: true
                    )
                )
            }
        }

        for generation in workspace.generations {
            let source = generation.generatorID.map(GraphPortProjection.generatorOutput)
                ?? .generationRunOutput(generation.id)
            for assetID in generation.outputAssetIDs {
                result.append(
                    GraphEdgeProjection(
                        id: .generationOutput(generationID: generation.id, assetID: assetID),
                        source: source,
                        target: .assetGenerationInput(assetID),
                        role: .lineage(.generationOutput(generation.id)),
                        isEditable: false
                    )
                )
            }
        }
        return result
    }
}
