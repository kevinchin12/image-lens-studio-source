import Foundation
import ImageLensCore

/// A lightweight, in-memory snapshot of canvas nodes selected for copying.
///
/// Assets, thumbnails, analysis snapshots, compiled prompts, generations, and
/// jobs are deliberately excluded. Image nodes retain their `AssetID`, so a
/// paste creates another canvas occurrence without duplicating image data.
public struct CanvasNodeCopyPayload: Equatable, Sendable {
    public let nodes: [CanvasNode]
    public let promptModules: [PromptModule]
    public let textBlocks: [TextBlock]
    public let recipes: [Recipe]
    public let generators: [Generator]
    public let generationGroups: [CanvasGenerationGroup]

    public init?(workspace: Workspace, selectedNodeIDs: Set<CanvasNodeID>) {
        let selectedNodes = workspace.canvasNodes.filter { selectedNodeIDs.contains($0.id) }
        guard !selectedNodes.isEmpty else { return nil }

        let moduleIDs = Set(selectedNodes.compactMap(\.promptModuleID))
        let textBlockIDs = Set(selectedNodes.compactMap(\.textBlockID))
        let generatorIDs = Set(selectedNodes.compactMap(\.generatorID))
        let selectedRecipeIDs = Set(selectedNodes.compactMap(\.recipeID))
        let selectedGenerators = workspace.generators.filter { generatorIDs.contains($0.id) }
        let recipeIDs = selectedRecipeIDs.union(selectedGenerators.map(\.recipeID))

        self.nodes = selectedNodes
        promptModules = workspace.promptModules.filter { moduleIDs.contains($0.id) }
        textBlocks = workspace.textBlocks.filter { textBlockIDs.contains($0.id) }
        recipes = workspace.recipes.filter { recipeIDs.contains($0.id) }
        generators = selectedGenerators
        generationGroups = workspace.generationGroups.filter { group in
            !group.memberNodeIDs.isEmpty
                && group.memberNodeIDs.allSatisfy(selectedNodeIDs.contains)
        }
    }

    public var nodeCount: Int { nodes.count }

    /// Instantiates fresh domain and canvas identities, appends them to the
    /// workspace, and returns the complete old-to-new mapping for selection.
    ///
    /// Recipe bindings owned by a copied recipe remain intact. A binding is
    /// remapped when its module was copied in the same payload and otherwise
    /// keeps referring to the existing module. Generator reference-image
    /// bindings similarly keep the same immutable `AssetID` while receiving a
    /// fresh binding identity.
    @discardableResult
    public func paste(
        into workspace: inout Workspace,
        offset: WorldSize,
        createdAt: Date = .now
    ) -> CanvasNodePasteResult {
        let moduleIDMap = Dictionary(uniqueKeysWithValues: promptModules.map { ($0.id, PromptModuleID()) })
        let textBlockIDMap = Dictionary(uniqueKeysWithValues: textBlocks.map { ($0.id, TextBlockID()) })
        let recipeIDMap = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, RecipeID()) })
        let generatorIDMap = Dictionary(uniqueKeysWithValues: generators.map { ($0.id, GeneratorID()) })
        let nodeIDMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, CanvasNodeID()) })
        let generationGroupIDMap = Dictionary(
            uniqueKeysWithValues: generationGroups.map { ($0.id, CanvasGenerationGroupID()) }
        )

        let pastedModules = promptModules.compactMap { source -> PromptModule? in
            guard let id = moduleIDMap[source.id] else { return nil }
            return PromptModule(
                id: id,
                role: source.role,
                content: source.content,
                sourceAssetID: source.sourceAssetID,
                sourceAnalysisSnapshotID: source.sourceAnalysisSnapshotID,
                evidence: source.evidence,
                evidenceClaims: source.evidenceClaims,
                isEnabled: source.isEnabled,
                isLocked: source.isLocked,
                revision: 0,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        }

        let pastedTextBlocks = textBlocks.compactMap { source -> TextBlock? in
            guard let id = textBlockIDMap[source.id] else { return nil }
            return TextBlock(
                id: id,
                kind: source.kind,
                text: source.text,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        }

        var reservedRecipeNames = workspace.recipes.map(\.name)
        let pastedRecipes = recipes.compactMap { source -> Recipe? in
            guard let id = recipeIDMap[source.id] else { return nil }
            let name = WorkspaceDisplayNamePolicy.copiedName(
                from: source.name,
                for: .recipe,
                existingNames: reservedRecipeNames
            )
            reservedRecipeNames.append(name)
            return Recipe(
                id: id,
                name: name,
                bindings: source.bindings.map { binding in
                    RecipeInputBinding(
                        id: RecipeBindingID(),
                        moduleID: moduleIDMap[binding.moduleID] ?? binding.moduleID,
                        role: binding.role,
                        order: binding.order,
                        priority: binding.priority,
                        isEnabled: binding.isEnabled
                    )
                },
                target: source.target,
                promptOverride: source.promptOverride,
                revision: 0,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        }

        var reservedGeneratorNames = workspace.generators.map(\.name)
        let pastedGenerators = generators.compactMap { source -> Generator? in
            guard let id = generatorIDMap[source.id] else { return nil }
            let name = WorkspaceDisplayNamePolicy.copiedName(
                from: source.name,
                for: .generator,
                existingNames: reservedGeneratorNames
            )
            reservedGeneratorNames.append(name)
            return Generator(
                id: id,
                name: name,
                recipeID: recipeIDMap[source.recipeID] ?? source.recipeID,
                promptText: source.promptText,
                target: source.target,
                parameters: source.parameters,
                assetBindings: source.assetBindings.map { binding in
                    GeneratorAssetBinding(
                        id: GeneratorAssetBindingID(),
                        assetID: binding.assetID,
                        sourceCanvasNodeID: binding.sourceCanvasNodeID.flatMap { nodeIDMap[$0] }
                            ?? binding.sourceCanvasNodeID,
                        role: binding.role,
                        order: binding.order,
                        isEnabled: binding.isEnabled
                    )
                },
                mediaKind: source.mediaKind,
                imageEdit: source.imageEdit,
                revision: 0,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        }

        let nextZIndex = (workspace.canvasNodes.map(\.zIndex).max() ?? -1) + 1
        let orderedNodes = nodes.sorted { lhs, rhs in
            if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
        let pastedNodes = orderedNodes.enumerated().compactMap { index, source -> CanvasNode? in
            guard let id = nodeIDMap[source.id] else { return nil }
            let entityID: UUID
            switch source.kind {
            case .image:
                // Image bytes, thumbnails, and analysis stay workspace-owned.
                entityID = source.entityID
            case .module:
                entityID = source.promptModuleID.flatMap { moduleIDMap[$0] }?.rawValue
                    ?? source.entityID
            case .text:
                entityID = source.textBlockID.flatMap { textBlockIDMap[$0] }?.rawValue
                    ?? source.entityID
            case .recipe:
                entityID = source.recipeID.flatMap { recipeIDMap[$0] }?.rawValue
                    ?? source.entityID
            case .generation:
                entityID = source.generatorID.flatMap { generatorIDMap[$0] }?.rawValue
                    ?? source.entityID
            }

            let pastedSize = source.kind == .generation
                ? WorldSize(
                    width: source.frame.width,
                    height: GeneratorNodeLayoutPolicy.normalizedHeight(source.frame.height)
                )
                : source.frame.size

            return CanvasNode(
                id: id,
                kind: source.kind,
                entityID: entityID,
                frame: WorldRect(
                    origin: WorldPoint(
                        x: source.frame.origin.x + offset.width,
                        y: source.frame.origin.y + offset.height
                    ),
                    size: pastedSize
                ),
                zIndex: nextZIndex + index,
                createdAt: createdAt
            )
        }

        var reservedGroupNames = workspace.generationGroups.compactMap(\.name)
        let pastedGenerationGroups = generationGroups.compactMap { source -> CanvasGenerationGroup? in
            guard let id = generationGroupIDMap[source.id] else { return nil }
            let memberNodeIDs = source.memberNodeIDs.compactMap { nodeIDMap[$0] }
            guard !memberNodeIDs.isEmpty else { return nil }
            let name = WorkspaceDisplayNamePolicy.copiedName(
                from: source.name ?? "",
                for: .generationGroup,
                existingNames: reservedGroupNames
            )
            reservedGroupNames.append(name)
            return CanvasGenerationGroup(
                id: id,
                generatorID: source.generatorID.map { generatorIDMap[$0] ?? $0 },
                name: name,
                memberNodeIDs: memberNodeIDs,
                origin: WorldPoint(
                    x: source.origin.x + offset.width,
                    y: source.origin.y + offset.height
                ),
                isCollapsed: source.isCollapsed,
                columns: source.columns,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        }

        workspace.promptModules.append(contentsOf: pastedModules)
        workspace.textBlocks.append(contentsOf: pastedTextBlocks)
        workspace.recipes.append(contentsOf: pastedRecipes)
        workspace.generators.append(contentsOf: pastedGenerators)
        workspace.canvasNodes.append(contentsOf: pastedNodes)
        workspace.generationGroups.append(contentsOf: pastedGenerationGroups)
        workspace.updatedAt = createdAt

        return CanvasNodePasteResult(
            nodes: pastedNodes,
            promptModules: pastedModules,
            textBlocks: pastedTextBlocks,
            recipes: pastedRecipes,
            generators: pastedGenerators,
            generationGroups: pastedGenerationGroups,
            nodeIDMap: nodeIDMap,
            moduleIDMap: moduleIDMap,
            textBlockIDMap: textBlockIDMap,
            recipeIDMap: recipeIDMap,
            generatorIDMap: generatorIDMap,
            generationGroupIDMap: generationGroupIDMap
        )
    }
}

public struct CanvasNodePasteResult: Equatable, Sendable {
    public let nodes: [CanvasNode]
    public let promptModules: [PromptModule]
    public let textBlocks: [TextBlock]
    public let recipes: [Recipe]
    public let generators: [Generator]
    public let generationGroups: [CanvasGenerationGroup]
    public let nodeIDMap: [CanvasNodeID: CanvasNodeID]
    public let moduleIDMap: [PromptModuleID: PromptModuleID]
    public let textBlockIDMap: [TextBlockID: TextBlockID]
    public let recipeIDMap: [RecipeID: RecipeID]
    public let generatorIDMap: [GeneratorID: GeneratorID]
    public let generationGroupIDMap: [CanvasGenerationGroupID: CanvasGenerationGroupID]

    public var nodeIDs: [CanvasNodeID] { nodes.map(\.id) }
}
