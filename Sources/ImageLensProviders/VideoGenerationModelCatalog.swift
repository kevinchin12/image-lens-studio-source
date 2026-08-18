import ImageLensCore

public enum VideoGenerationModelLifecycle: String, Equatable, Sendable {
    case stable
    case preview
    case legacy
}

public struct VideoGenerationModelDescriptor: Equatable, Sendable {
    public var providerID: ProviderID
    public var modelID: String
    public var displayName: String
    public var shortDisplayName: String
    public var summary: String
    public var supportedAspectRatios: [String]
    public var maxReferenceImages: Int
    public var supportedReferenceMediaKinds: Set<AssetMediaKind>
    public var lifecycle: VideoGenerationModelLifecycle

    public init(
        providerID: ProviderID,
        modelID: String,
        displayName: String,
        shortDisplayName: String,
        summary: String,
        supportedAspectRatios: [String],
        maxReferenceImages: Int,
        supportedReferenceMediaKinds: Set<AssetMediaKind>,
        lifecycle: VideoGenerationModelLifecycle
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.displayName = displayName
        self.shortDisplayName = shortDisplayName
        self.summary = summary
        self.supportedAspectRatios = supportedAspectRatios
        self.maxReferenceImages = maxReferenceImages
        self.supportedReferenceMediaKinds = supportedReferenceMediaKinds
        self.lifecycle = lifecycle
    }
}

public struct VideoGenerationProviderDescriptor: Equatable, Sendable {
    public var id: ProviderID
    public var displayName: String
    public var models: [VideoGenerationModelDescriptor]
    public var defaultModelID: String

    public init(
        id: ProviderID,
        displayName: String,
        models: [VideoGenerationModelDescriptor],
        defaultModelID: String
    ) {
        self.id = id
        self.displayName = displayName
        self.models = models
        self.defaultModelID = defaultModelID
    }
}

/// Presentation and capability metadata for video-generation services.
///
/// Gemini Omni deliberately advertises image references only. Although the
/// preview API accepts video-shaped input, Google currently documents that
/// video references are not processed correctly by the model.
public enum VideoGenerationModelCatalog {
    public static let geminiProviderID = ImageGenerationModelCatalog.geminiProviderID

    public static let geminiOmniFlash = VideoGenerationModelDescriptor(
        providerID: geminiProviderID,
        modelID: "gemini-omni-flash-preview",
        displayName: "Gemini Omni Flash",
        shortDisplayName: "Omni Flash",
        summary: "快速视频生成与多模态参考",
        supportedAspectRatios: ["16:9", "9:16"],
        maxReferenceImages: 6,
        supportedReferenceMediaKinds: [.image],
        lifecycle: .preview
    )

    public static let gemini = VideoGenerationProviderDescriptor(
        id: geminiProviderID,
        displayName: "Google Gemini",
        models: [geminiOmniFlash],
        defaultModelID: geminiOmniFlash.modelID
    )

    public static let providers = [gemini]

    public static func provider(id: ProviderID) -> VideoGenerationProviderDescriptor? {
        providers.first { $0.id == id }
    }

    public static func model(
        providerID: ProviderID,
        modelID: String
    ) -> VideoGenerationModelDescriptor? {
        provider(id: providerID)?.models.first { $0.modelID == modelID }
    }
}
