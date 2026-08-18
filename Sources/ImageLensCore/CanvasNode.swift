import Foundation

/// The intentionally small object vocabulary supported by the canvas.
public enum CanvasNodeKind: String, Codable, CaseIterable, Sendable {
    case image
    case module
    case text
    case recipe
    case generation
}

/// Canonical persisted placement for an entity shown on the canvas.
///
/// `kind` gives `entityID` its domain meaning. Typed initializers and accessors
/// keep feature code from accidentally connecting an ID to the wrong node kind,
/// while the UUID representation keeps the persisted schema compact and stable.
public struct CanvasNode: Codable, Equatable, Identifiable, Sendable {
    public var id: CanvasNodeID
    public var kind: CanvasNodeKind
    public var entityID: UUID
    public var frame: WorldRect
    public var zIndex: Int
    public var createdAt: Date

    public init(
        id: CanvasNodeID = CanvasNodeID(),
        kind: CanvasNodeKind,
        entityID: UUID,
        frame: WorldRect,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.entityID = entityID
        self.frame = frame.standardized
        self.zIndex = zIndex
        self.createdAt = createdAt
    }

    public init(
        id: CanvasNodeID = CanvasNodeID(),
        imageAssetID: AssetID,
        frame: WorldRect,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.init(
            id: id,
            kind: .image,
            entityID: imageAssetID.rawValue,
            frame: frame,
            zIndex: zIndex,
            createdAt: createdAt
        )
    }

    public init(
        id: CanvasNodeID = CanvasNodeID(),
        promptModuleID: PromptModuleID,
        frame: WorldRect,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.init(
            id: id,
            kind: .module,
            entityID: promptModuleID.rawValue,
            frame: frame,
            zIndex: zIndex,
            createdAt: createdAt
        )
    }

    public init(
        id: CanvasNodeID = CanvasNodeID(),
        textBlockID: TextBlockID,
        frame: WorldRect,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.init(
            id: id,
            kind: .text,
            entityID: textBlockID.rawValue,
            frame: frame,
            zIndex: zIndex,
            createdAt: createdAt
        )
    }

    public init(
        id: CanvasNodeID = CanvasNodeID(),
        recipeID: RecipeID,
        frame: WorldRect,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.init(
            id: id,
            kind: .recipe,
            entityID: recipeID.rawValue,
            frame: frame,
            zIndex: zIndex,
            createdAt: createdAt
        )
    }

    public init(
        id: CanvasNodeID = CanvasNodeID(),
        generatorID: GeneratorID,
        frame: WorldRect,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.init(
            id: id,
            kind: .generation,
            entityID: generatorID.rawValue,
            frame: frame,
            zIndex: zIndex,
            createdAt: createdAt
        )
    }

    /// Legacy convenience for pre-Generator workspaces. New code should place
    /// editable `Generator` entities rather than immutable generation records.
    public init(
        id: CanvasNodeID = CanvasNodeID(),
        generationID: GenerationID,
        frame: WorldRect,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.init(
            id: id,
            kind: .generation,
            entityID: generationID.rawValue,
            frame: frame,
            zIndex: zIndex,
            createdAt: createdAt
        )
    }

    public var imageAssetID: AssetID? {
        kind == .image ? AssetID(entityID) : nil
    }

    public var promptModuleID: PromptModuleID? {
        kind == .module ? PromptModuleID(entityID) : nil
    }

    public var textBlockID: TextBlockID? {
        kind == .text ? TextBlockID(entityID) : nil
    }

    public var recipeID: RecipeID? {
        kind == .recipe ? RecipeID(entityID) : nil
    }

    public var generatorID: GeneratorID? {
        kind == .generation ? GeneratorID(entityID) : nil
    }

    public var generationID: GenerationID? {
        kind == .generation ? GenerationID(entityID) : nil
    }
}
