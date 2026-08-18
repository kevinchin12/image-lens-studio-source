import ImageLensCore

public enum ImageGenerationModelLifecycle: String, Equatable, Sendable {
    case stable
    case legacy
}

public struct ImageGenerationModelDescriptor: Equatable, Sendable {
    public var providerID: ProviderID
    public var modelID: String
    public var displayName: String
    public var shortDisplayName: String
    public var summary: String
    public var supportedAspectRatios: [String]
    public var supportedImageSizes: [String]
    public var maxReferenceImages: Int
    public var supportedReferenceMediaKinds: Set<AssetMediaKind>
    public var lifecycle: ImageGenerationModelLifecycle

    public init(
        providerID: ProviderID,
        modelID: String,
        displayName: String,
        shortDisplayName: String,
        summary: String,
        supportedAspectRatios: [String],
        supportedImageSizes: [String],
        maxReferenceImages: Int,
        supportedReferenceMediaKinds: Set<AssetMediaKind> = [.image],
        lifecycle: ImageGenerationModelLifecycle = .stable
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.displayName = displayName
        self.shortDisplayName = shortDisplayName
        self.summary = summary
        self.supportedAspectRatios = supportedAspectRatios
        self.supportedImageSizes = supportedImageSizes
        self.maxReferenceImages = maxReferenceImages
        self.supportedReferenceMediaKinds = supportedReferenceMediaKinds
        self.lifecycle = lifecycle
    }
}

public struct ImageGenerationProviderDescriptor: Equatable, Sendable {
    public var id: ProviderID
    public var displayName: String
    public var models: [ImageGenerationModelDescriptor]
    public var defaultModelID: String

    public init(
        id: ProviderID,
        displayName: String,
        models: [ImageGenerationModelDescriptor],
        defaultModelID: String
    ) {
        self.id = id
        self.displayName = displayName
        self.models = models
        self.defaultModelID = defaultModelID
    }
}

/// Presentation and capability metadata for image-generation services.
///
/// Workspace manifests continue to store open-ended provider and model IDs. The
/// catalog enriches known targets without rewriting unknown or legacy values.
public enum ImageGenerationModelCatalog {
    public static let geminiProviderID: ProviderID = "gemini"

    private static let commonAspectRatios = [
        "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"
    ]

    public static let geminiModels: [ImageGenerationModelDescriptor] = [
        ImageGenerationModelDescriptor(
            providerID: geminiProviderID,
            modelID: "gemini-3.1-flash-lite-image",
            displayName: "Nano Banana 2 Lite",
            shortDisplayName: "NB 2 Lite",
            summary: "最快、成本最低 · 1K 输出",
            supportedAspectRatios: commonAspectRatios,
            supportedImageSizes: ["1K"],
            maxReferenceImages: 14,
            supportedReferenceMediaKinds: [.image, .video]
        ),
        ImageGenerationModelDescriptor(
            providerID: geminiProviderID,
            modelID: "gemini-3.1-flash-image",
            displayName: "Nano Banana 2",
            shortDisplayName: "NB 2",
            summary: "通用主力 · 速度与质量均衡",
            supportedAspectRatios: [
                "1:1", "1:4", "1:8", "2:3", "3:2", "3:4", "4:1", "4:3", "4:5", "5:4",
                "8:1", "9:16", "16:9", "21:9"
            ],
            supportedImageSizes: ["512", "1K", "2K", "4K"],
            maxReferenceImages: 14,
            supportedReferenceMediaKinds: [.image, .video]
        ),
        ImageGenerationModelDescriptor(
            providerID: geminiProviderID,
            modelID: "gemini-3-pro-image",
            displayName: "Nano Banana Pro",
            shortDisplayName: "NB Pro",
            summary: "复杂创作 · 最高控制力与一致性",
            supportedAspectRatios: commonAspectRatios,
            supportedImageSizes: ["1K", "2K", "4K"],
            maxReferenceImages: 14,
            supportedReferenceMediaKinds: [.image]
        )
    ]

    public static let gemini = ImageGenerationProviderDescriptor(
        id: geminiProviderID,
        displayName: "Google Gemini",
        models: geminiModels,
        defaultModelID: "gemini-3.1-flash-image"
    )

    public static let providers: [ImageGenerationProviderDescriptor] = [gemini]

    public static func provider(id: ProviderID) -> ImageGenerationProviderDescriptor? {
        providers.first { $0.id == id }
    }

    public static func model(
        providerID: ProviderID,
        modelID: String
    ) -> ImageGenerationModelDescriptor? {
        provider(id: providerID)?.models.first { $0.modelID == modelID }
    }
}
