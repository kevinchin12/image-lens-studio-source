import Foundation
import ImageLensCore

public enum ProviderMediaSource: Equatable, Sendable {
    case inline(Data)
    case managedFile(URL)
}

public struct ProviderMediaInput: Equatable, Sendable {
    public var source: ProviderMediaSource
    public var mimeType: String
    public var mediaKind: AssetMediaKind
    public var referenceRoles: [GeneratorAssetRole]

    public init(
        source: ProviderMediaSource,
        mimeType: String,
        mediaKind: AssetMediaKind,
        referenceRoles: [GeneratorAssetRole] = []
    ) {
        self.source = source
        self.mimeType = mimeType
        self.mediaKind = mediaKind
        self.referenceRoles = referenceRoles
    }
}

/// Gemini currently treats the mask as a second semantic image rather than a
/// native pixel-locked mask. Keeping that limitation in the type prevents the
/// beta contract from being mistaken for a precise provider capability.
public enum ImageEditMode: String, Equatable, Sendable {
    case semanticMaskBeta
}

public struct ImageEditInput: Equatable, Sendable {
    public var source: ProviderMediaInput
    public var mask: ProviderMediaInput
    public var mode: ImageEditMode

    public init(
        source: ProviderMediaInput,
        mask: ProviderMediaInput,
        mode: ImageEditMode = .semanticMaskBeta
    ) {
        self.source = source
        self.mask = mask
        self.mode = mode
    }
}

public struct ImageGenerationRequest: Equatable, Sendable {
    public var target: CompileTarget
    public var prompt: String
    public var referenceMedia: [ProviderMediaInput]
    public var editInput: ImageEditInput?
    public var aspectRatio: String
    public var providerOptions: [String: String]

    public init(
        target: CompileTarget,
        prompt: String,
        referenceMedia: [ProviderMediaInput] = [],
        editInput: ImageEditInput? = nil,
        aspectRatio: String,
        providerOptions: [String: String] = [:]
    ) {
        self.target = target
        self.prompt = prompt
        self.referenceMedia = referenceMedia
        self.editInput = editInput
        self.aspectRatio = aspectRatio
        self.providerOptions = providerOptions
    }
}

public protocol ImageGenerationProvider: Sendable {
    var providerID: ProviderID { get }

    func generate(
        request: ImageGenerationRequest,
        credential: String
    ) async throws -> [GeneratedImagePayload]
}
