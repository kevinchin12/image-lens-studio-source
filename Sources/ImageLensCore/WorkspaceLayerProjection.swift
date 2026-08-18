import Foundation

/// The user-facing categories used by the canvas layer list.
///
/// Generation groups are presentation metadata for generated image
/// occurrences. They intentionally do not become a separate layer category.
public enum WorkspaceLayerKind: String, CaseIterable, Hashable, Sendable {
    case sourceImages
    case generatedImages
    case promptModules
    case textBlocks
    case recipes
    case generators

    public var displayName: String {
        switch self {
        case .sourceImages: "图片"
        case .generatedImages: "生成结果"
        case .promptModules: "提示词"
        case .textBlocks: "文本"
        case .recipes: "提示词组合"
        case .generators: "生图节点"
        }
    }
}

/// A typed reference to the persisted entity represented by one canvas
/// occurrence.
public enum WorkspaceLayerEntity: Hashable, Sendable {
    case asset(AssetID)
    case promptModule(PromptModuleID)
    case textBlock(TextBlockID)
    case recipe(RecipeID)
    case generator(GeneratorID)

    public var rawID: UUID {
        switch self {
        case .asset(let id): id.rawValue
        case .promptModule(let id): id.rawValue
        case .textBlock(let id): id.rawValue
        case .recipe(let id): id.rawValue
        case .generator(let id): id.rawValue
        }
    }
}

/// A lightweight row for one persisted canvas occurrence.
///
/// The row ID is the canvas node ID rather than the entity ID. This preserves
/// separate rows when copied image nodes reference the same underlying asset.
public struct WorkspaceLayerRow: Identifiable, Equatable, Sendable {
    public var id: CanvasNodeID { nodeID }
    public let nodeID: CanvasNodeID
    public let kind: WorkspaceLayerKind
    public let entity: WorkspaceLayerEntity
    public let title: String
    public let secondaryDetail: String
    public let zIndex: Int
    public let createdAt: Date
    public let generationGroupID: CanvasGenerationGroupID?
    public let generationGroupName: String?
    public let generationGroupOrdinal: Int?

    public var entityID: UUID { entity.rawID }

    public var imageAssetID: AssetID? {
        guard case .asset(let id) = entity else { return nil }
        return id
    }

    public var promptModuleID: PromptModuleID? {
        guard case .promptModule(let id) = entity else { return nil }
        return id
    }

    public var recipeID: RecipeID? {
        guard case .recipe(let id) = entity else { return nil }
        return id
    }

    public var textBlockID: TextBlockID? {
        guard case .textBlock(let id) = entity else { return nil }
        return id
    }

    public var generatorID: GeneratorID? {
        guard case .generator(let id) = entity else { return nil }
        return id
    }

    public init(
        nodeID: CanvasNodeID,
        kind: WorkspaceLayerKind,
        entity: WorkspaceLayerEntity,
        title: String,
        secondaryDetail: String,
        zIndex: Int,
        createdAt: Date,
        generationGroupID: CanvasGenerationGroupID? = nil,
        generationGroupName: String? = nil,
        generationGroupOrdinal: Int? = nil
    ) {
        self.nodeID = nodeID
        self.kind = kind
        self.entity = entity
        self.title = title
        self.secondaryDetail = secondaryDetail
        self.zIndex = zIndex
        self.createdAt = createdAt
        self.generationGroupID = generationGroupID
        self.generationGroupName = generationGroupName
        self.generationGroupOrdinal = generationGroupOrdinal
    }
}

public struct WorkspaceLayerSection: Identifiable, Equatable, Sendable {
    public var id: WorkspaceLayerKind { kind }
    public let kind: WorkspaceLayerKind
    public let rows: [WorkspaceLayerRow]

    public var title: String { kind.displayName }
    public var count: Int { rows.count }

    public init(kind: WorkspaceLayerKind, rows: [WorkspaceLayerRow]) {
        self.kind = kind
        self.rows = rows
    }
}

/// Builds a stable, read-only layer-list projection from the current canvas.
public enum WorkspaceLayerProjection {
    /// Returns sections in the fixed user-facing order declared by
    /// `WorkspaceLayerKind.allCases`.
    ///
    /// Rows within a section use the conventional layer-list order: highest
    /// z-index first. Creation time and node ID provide deterministic
    /// tie-breakers, so the result does not depend on input collection order.
    public static func sections(
        in workspace: Workspace,
        includeEmptySections: Bool = false
    ) -> [WorkspaceLayerSection] {
        let rowsByKind = Dictionary(grouping: rows(in: workspace), by: \.kind)

        return WorkspaceLayerKind.allCases.compactMap { kind in
            let rows = rowsByKind[kind] ?? []
            guard includeEmptySections || !rows.isEmpty else { return nil }
            return WorkspaceLayerSection(kind: kind, rows: rows)
        }
    }

    /// Returns all canvas occurrences in stable layer order.
    public static func rows(in workspace: Workspace) -> [WorkspaceLayerRow] {
        let assetByID = Dictionary(uniqueKeysWithValues: workspace.assets.map { ($0.id, $0) })
        let moduleByID = Dictionary(
            uniqueKeysWithValues: workspace.promptModules.map { ($0.id, $0) }
        )
        let textBlockByID = Dictionary(
            uniqueKeysWithValues: workspace.textBlocks.map { ($0.id, $0) }
        )
        let recipeByID = Dictionary(
            uniqueKeysWithValues: workspace.recipes.map { ($0.id, $0) }
        )
        let generatorByID = Dictionary(
            uniqueKeysWithValues: workspace.generators.map { ($0.id, $0) }
        )
        let generationByAssetID = generationLookup(workspace)
        let groupByNodeID = generationGroupLookup(workspace.generationGroups)

        return workspace.canvasNodes.map { node in
            switch node.kind {
            case .image:
                let assetID = AssetID(node.entityID)
                let asset = assetByID[assetID]
                let groupContext = groupByNodeID[node.id]
                let generation = asset.flatMap { generationByAssetID[$0.id] }
                let kind: WorkspaceLayerKind = asset?.kind == .generated
                    ? .generatedImages
                    : .sourceImages
                return imageRow(
                    node: node,
                    assetID: assetID,
                    asset: asset,
                    kind: kind,
                    generation: generation,
                    groupContext: groupContext,
                    generators: generatorByID,
                    compiledPrompts: workspace.compiledPrompts,
                    recipes: workspace.recipes
                )

            case .module:
                let moduleID = PromptModuleID(node.entityID)
                return moduleRow(
                    node: node,
                    moduleID: moduleID,
                    module: moduleByID[moduleID]
                )

            case .text:
                let textBlockID = TextBlockID(node.entityID)
                return textBlockRow(
                    node: node,
                    textBlockID: textBlockID,
                    textBlock: textBlockByID[textBlockID]
                )

            case .recipe:
                let recipeID = RecipeID(node.entityID)
                return recipeRow(
                    node: node,
                    recipeID: recipeID,
                    recipe: recipeByID[recipeID]
                )

            case .generation:
                let generatorID = GeneratorID(node.entityID)
                return generatorRow(
                    node: node,
                    generatorID: generatorID,
                    generator: generatorByID[generatorID],
                    recipeByID: recipeByID
                )
            }
        }
        .sorted(by: layerRowComesFirst)
    }

    private static func imageRow(
        node: CanvasNode,
        assetID: AssetID,
        asset: Asset?,
        kind: WorkspaceLayerKind,
        generation: GenerationRecord?,
        groupContext: GenerationGroupContext?,
        generators: [GeneratorID: Generator],
        compiledPrompts: [CompiledPromptSnapshot],
        recipes: [Recipe]
    ) -> WorkspaceLayerRow {
        guard let asset else {
            return WorkspaceLayerRow(
                nodeID: node.id,
                kind: kind,
                entity: .asset(assetID),
                title: "缺失图片",
                secondaryDetail: "资源已丢失",
                zIndex: node.zIndex,
                createdAt: node.createdAt,
                generationGroupID: groupContext?.group.id,
                generationGroupName: groupContext?.name,
                generationGroupOrdinal: groupContext?.ordinal
            )
        }

        let dimensions = dimensionDetail(asset.pixelSize)
        if kind == .generatedImages {
            let fallbackTitle = generatedImageTitle(
                asset: asset,
                generation: generation,
                generators: generators,
                compiledPrompts: compiledPrompts,
                recipes: recipes
            )
            let titleBase = groupContext?.name ?? fallbackTitle
            let title = groupContext.map {
                "\(titleBase) · 第 \($0.ordinal) 张"
            } ?? titleBase
            return WorkspaceLayerRow(
                nodeID: node.id,
                kind: kind,
                entity: .asset(assetID),
                title: title,
                secondaryDetail: joinedDetail(["生成结果", dimensions]),
                zIndex: node.zIndex,
                createdAt: node.createdAt,
                generationGroupID: groupContext?.group.id,
                generationGroupName: groupContext?.name,
                generationGroupOrdinal: groupContext?.ordinal
            )
        }

        return WorkspaceLayerRow(
            nodeID: node.id,
            kind: kind,
            entity: .asset(assetID),
            title: readableName(asset.displayName, fallback: "未命名图片"),
            secondaryDetail: joinedDetail(["原图", dimensions]),
            zIndex: node.zIndex,
            createdAt: node.createdAt
        )
    }

    private static func moduleRow(
        node: CanvasNode,
        moduleID: PromptModuleID,
        module: PromptModule?
    ) -> WorkspaceLayerRow {
        guard let module else {
            return WorkspaceLayerRow(
                nodeID: node.id,
                kind: .promptModules,
                entity: .promptModule(moduleID),
                title: "缺失提示词",
                secondaryDetail: "内容已丢失",
                zIndex: node.zIndex,
                createdAt: node.createdAt
            )
        }

        let title: String
        switch module.role {
        case .visual(let category):
            title = category.displayName
        case .instruction:
            title = "创作指令"
        }

        return WorkspaceLayerRow(
            nodeID: node.id,
            kind: .promptModules,
            entity: .promptModule(moduleID),
            title: title,
            secondaryDetail: compact(module.content, maximumLength: 56, fallback: "空白提示词"),
            zIndex: node.zIndex,
            createdAt: node.createdAt
        )
    }

    private static func textBlockRow(
        node: CanvasNode,
        textBlockID: TextBlockID,
        textBlock: TextBlock?
    ) -> WorkspaceLayerRow {
        WorkspaceLayerRow(
            nodeID: node.id,
            kind: .textBlocks,
            entity: .textBlock(textBlockID),
            title: "备注",
            secondaryDetail: compact(
                textBlock?.text ?? "",
                maximumLength: 56,
                fallback: textBlock == nil ? "内容已丢失" : "空白备注"
            ),
            zIndex: node.zIndex,
            createdAt: node.createdAt
        )
    }

    private static func recipeRow(
        node: CanvasNode,
        recipeID: RecipeID,
        recipe: Recipe?
    ) -> WorkspaceLayerRow {
        WorkspaceLayerRow(
            nodeID: node.id,
            kind: .recipes,
            entity: .recipe(recipeID),
            title: recipe.map {
                readableName($0.name, fallback: "未命名提示词组合")
            } ?? "缺失提示词组合",
            secondaryDetail: recipe.map {
                "\($0.bindings.filter(\.isEnabled).count) 个提示词模块"
            } ?? "内容已丢失",
            zIndex: node.zIndex,
            createdAt: node.createdAt
        )
    }

    private static func generatorRow(
        node: CanvasNode,
        generatorID: GeneratorID,
        generator: Generator?,
        recipeByID: [RecipeID: Recipe]
    ) -> WorkspaceLayerRow {
        let enabledModuleCount = generator
            .flatMap { recipeByID[$0.recipeID] }?
            .bindings
            .filter(\.isEnabled)
            .count

        return WorkspaceLayerRow(
            nodeID: node.id,
            kind: .generators,
            entity: .generator(generatorID),
            title: generator.map {
                readableName($0.name, fallback: "未命名生图节点")
            } ?? "缺失生图节点",
            secondaryDetail: generator.map {
                joinedDetail([
                    $0.parameters.aspectRatio,
                    enabledModuleCount.map { "\($0) 个提示词模块" }
                ])
            } ?? "内容已丢失",
            zIndex: node.zIndex,
            createdAt: node.createdAt
        )
    }

    private static func generatedImageTitle(
        asset: Asset,
        generation: GenerationRecord?,
        generators: [GeneratorID: Generator],
        compiledPrompts: [CompiledPromptSnapshot],
        recipes: [Recipe]
    ) -> String {
        guard let generation else {
            return readableName(asset.displayName, fallback: "未命名生成结果")
        }

        let generator = generation.generatorID.flatMap { generators[$0] }
        let compiledPrompt = compiledPrompts.first { $0.id == generation.promptSnapshotID }
        let recipe = recipes.first { $0.id == generation.recipeID }
        return GenerationHistoryTitlePolicy.baseTitle(
            generatorName: generation.generatorNameSnapshot ?? generator?.name,
            compiledPrompt: compiledPrompt,
            recipe: recipe
        )
    }

    private static func generationLookup(
        _ workspace: Workspace
    ) -> [AssetID: GenerationRecord] {
        var result: [AssetID: GenerationRecord] = [:]
        for generation in workspace.generations.sorted(by: generationComesFirst) {
            for assetID in generation.outputAssetIDs where result[assetID] == nil {
                result[assetID] = generation
            }
        }
        for asset in workspace.assets {
            guard asset.isResult,
                  result[asset.id] == nil,
                  let generationID = asset.sourceGenerationID,
                  let generation = workspace.generations.first(where: { $0.id == generationID })
            else {
                continue
            }
            result[asset.id] = generation
        }
        return result
    }

    private static func generationGroupLookup(
        _ groups: [CanvasGenerationGroup]
    ) -> [CanvasNodeID: GenerationGroupContext] {
        var result: [CanvasNodeID: GenerationGroupContext] = [:]
        for group in groups.sorted(by: generationGroupComesFirst) {
            let name = normalizedOptional(group.name)
            for (offset, nodeID) in group.memberNodeIDs.enumerated()
                where result[nodeID] == nil {
                result[nodeID] = GenerationGroupContext(
                    group: group,
                    name: name,
                    ordinal: offset + 1
                )
            }
        }
        return result
    }

    private static func generationComesFirst(
        _ lhs: GenerationRecord,
        _ rhs: GenerationRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return uuidString(lhs.id.rawValue) < uuidString(rhs.id.rawValue)
    }

    private static func generationGroupComesFirst(
        _ lhs: CanvasGenerationGroup,
        _ rhs: CanvasGenerationGroup
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return uuidString(lhs.id.rawValue) < uuidString(rhs.id.rawValue)
    }

    private static func layerRowComesFirst(
        _ lhs: WorkspaceLayerRow,
        _ rhs: WorkspaceLayerRow
    ) -> Bool {
        if lhs.kind != rhs.kind {
            return kindIndex(lhs.kind) < kindIndex(rhs.kind)
        }
        if lhs.zIndex != rhs.zIndex {
            return lhs.zIndex > rhs.zIndex
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return uuidString(lhs.nodeID.rawValue) < uuidString(rhs.nodeID.rawValue)
    }

    private static func kindIndex(_ kind: WorkspaceLayerKind) -> Int {
        WorkspaceLayerKind.allCases.firstIndex(of: kind) ?? .max
    }

    private static func dimensionDetail(_ size: PixelSize?) -> String? {
        guard let size, size.width > 0, size.height > 0 else { return nil }
        return "\(size.width) × \(size.height)"
    }

    private static func joinedDetail(_ components: [String?]) -> String {
        components.compactMap { component in
            guard let component else { return nil }
            let normalized = normalized(component)
            return normalized.isEmpty ? nil : normalized
        }
        .joined(separator: " · ")
    }

    private static func readableName(_ value: String, fallback: String) -> String {
        let normalized = normalized(value)
        return normalized.isEmpty ? fallback : normalized
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalized(value)
        return normalized.isEmpty ? nil : normalized
    }

    private static func compact(
        _ value: String,
        maximumLength: Int,
        fallback: String
    ) -> String {
        let value = normalized(value)
        guard !value.isEmpty else { return fallback }
        guard value.count > maximumLength else { return value }
        return String(value.prefix(maximumLength - 1)) + "…"
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uuidString(_ id: UUID) -> String {
        id.uuidString
    }

    private struct GenerationGroupContext {
        let group: CanvasGenerationGroup
        let name: String?
        let ordinal: Int
    }
}
