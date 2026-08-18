import Foundation

public struct EntityID<Tag>: Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum WorkspaceIdentity: Sendable {}
public enum AssetIdentity: Sendable {}
public enum AnalysisSnapshotIdentity: Sendable {}
public enum PromptModuleIdentity: Sendable {}
public enum TextBlockIdentity: Sendable {}
public enum RecipeIdentity: Sendable {}
public enum RecipeBindingIdentity: Sendable {}
public enum CompiledPromptIdentity: Sendable {}
public enum GeneratorIdentity: Sendable {}
public enum GeneratorAssetBindingIdentity: Sendable {}
public enum GenerationIdentity: Sendable {}
public enum JobIdentity: Sendable {}
public enum CanvasNodeIdentity: Sendable {}
public enum CanvasGenerationGroupIdentity: Sendable {}

public typealias WorkspaceID = EntityID<WorkspaceIdentity>
public typealias AssetID = EntityID<AssetIdentity>
public typealias AnalysisSnapshotID = EntityID<AnalysisSnapshotIdentity>
public typealias PromptModuleID = EntityID<PromptModuleIdentity>
public typealias TextBlockID = EntityID<TextBlockIdentity>
public typealias RecipeID = EntityID<RecipeIdentity>
public typealias RecipeBindingID = EntityID<RecipeBindingIdentity>
public typealias CompiledPromptID = EntityID<CompiledPromptIdentity>
public typealias GeneratorID = EntityID<GeneratorIdentity>
public typealias GeneratorAssetBindingID = EntityID<GeneratorAssetBindingIdentity>
public typealias GenerationID = EntityID<GenerationIdentity>
public typealias JobID = EntityID<JobIdentity>
public typealias CanvasNodeID = EntityID<CanvasNodeIdentity>
public typealias CanvasGenerationGroupID = EntityID<CanvasGenerationGroupIdentity>

public struct ProviderID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}
