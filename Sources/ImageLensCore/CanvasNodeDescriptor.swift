import Foundation

/// The small, user-facing vocabulary of objects on the creative canvas.
///
/// Persisted `CanvasNodeKind` stays a compact storage vocabulary. This
/// projection lets capabilities reason about media, text, actions, and results
/// without teaching every feature about legacy entity storage.
public enum CanvasNodeFamily: String, CaseIterable, Codable, Sendable {
    case media
    case text
    case action
    case result
    case internalObject
}

/// Stable built-in type identifiers. Future provider or capability packs may
/// contribute descriptors without adding another persisted canvas-node case.
public enum CanvasNodeTypeID: String, CaseIterable, Codable, Sendable {
    case image = "media.image"
    case video = "media.video"
    case promptModule = "text.prompt-module"
    case instruction = "text.instruction"
    case note = "text.note"
    case imageGeneration = "action.image-generation"
    case videoGeneration = "action.video-generation"
    case generatedImage = "result.image"
    case generatedVideo = "result.video"
    case promptRecipe = "internal.prompt-recipe"
    case unavailable = "internal.unavailable"
}

public enum CanvasNodeCapability: String, CaseIterable, Codable, Sendable {
    case inspect
    case rename
    case resize
    case copy
    case remove
    case editText
    case connect
    case analyzeImage
    case useAsReference
    case run
    case cancelRun
    case group
    case export
    case playback
}

public struct CanvasNodeDescriptor: Equatable, Sendable {
    public var typeID: CanvasNodeTypeID
    public var family: CanvasNodeFamily
    public var capabilities: Set<CanvasNodeCapability>

    public init(
        typeID: CanvasNodeTypeID,
        family: CanvasNodeFamily,
        capabilities: Set<CanvasNodeCapability>
    ) {
        self.typeID = typeID
        self.family = family
        self.capabilities = capabilities
    }

    public func supports(_ capability: CanvasNodeCapability) -> Bool {
        capabilities.contains(capability)
    }
}

/// Built-in registry for the current project schema.
///
/// It is deliberately a pure projection: no duplicate node state is persisted,
/// and an existing workspace therefore gains the generic vocabulary without a
/// migration or visual change.
public enum CanvasNodeRegistry {
    public static func descriptor(
        for node: CanvasNode,
        in workspace: Workspace
    ) -> CanvasNodeDescriptor {
        switch node.kind {
        case .image:
            guard let assetID = node.imageAssetID,
                  let asset = workspace.assets.first(where: { $0.id == assetID }) else {
                return unavailable
            }
            return descriptor(for: asset)

        case .module:
            guard let moduleID = node.promptModuleID,
                  let module = workspace.promptModules.first(where: { $0.id == moduleID }) else {
                return unavailable
            }
            let typeID: CanvasNodeTypeID
            switch module.role {
            case .visual: typeID = .promptModule
            case .instruction: typeID = .instruction
            }
            return CanvasNodeDescriptor(
                typeID: typeID,
                family: .text,
                capabilities: [.inspect, .copy, .remove, .editText, .connect]
            )

        case .text:
            guard let textBlockID = node.textBlockID,
                  workspace.textBlocks.contains(where: { $0.id == textBlockID }) else {
                return unavailable
            }
            return CanvasNodeDescriptor(
                typeID: .note,
                family: .text,
                capabilities: [.inspect, .copy, .remove, .editText]
            )

        case .generation:
            let editableGenerator = node.generatorID.flatMap { generatorID in
                workspace.generators.first { $0.id == generatorID }
            }
            let legacyRun = node.generationID.flatMap { generationID in
                workspace.generations.first { $0.id == generationID }
            }
            guard editableGenerator != nil || legacyRun != nil else { return unavailable }
            let mediaKind = editableGenerator?.mediaKind ?? legacyRun?.mediaKind ?? .image
            return CanvasNodeDescriptor(
                typeID: mediaKind == .video ? .videoGeneration : .imageGeneration,
                family: .action,
                capabilities: editableGenerator != nil
                    ? [.inspect, .rename, .copy, .remove, .connect, .run, .cancelRun]
                    : [.inspect, .copy, .remove]
            )

        case .recipe:
            return CanvasNodeDescriptor(
                typeID: .promptRecipe,
                family: .internalObject,
                capabilities: [.inspect, .copy, .remove]
            )
        }
    }

    public static func descriptor(for asset: Asset) -> CanvasNodeDescriptor {
        let shared: Set<CanvasNodeCapability> = [
            .inspect, .copy, .remove, .export
        ]

        if asset.isResult && !asset.isMaterial {
            return CanvasNodeDescriptor(
                typeID: asset.isVideo ? .generatedVideo : .generatedImage,
                family: .result,
                capabilities: shared.union([.useAsReference, .group])
            )
        }

        if asset.isVideo {
            return CanvasNodeDescriptor(
                typeID: .video,
                family: .media,
                capabilities: shared.union([.playback, .useAsReference])
            )
        }

        var capabilities = shared.union([.useAsReference])
        if asset.supportsReversePrompt {
            capabilities.insert(.analyzeImage)
        }
        return CanvasNodeDescriptor(
            typeID: .image,
            family: .media,
            capabilities: capabilities
        )
    }

    private static let unavailable = CanvasNodeDescriptor(
        typeID: .unavailable,
        family: .internalObject,
        capabilities: [.remove]
    )
}
