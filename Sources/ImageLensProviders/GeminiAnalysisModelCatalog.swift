public struct GeminiAnalysisModelDescriptor: Equatable, Sendable {
    public var modelID: String
    public var displayName: String
    public var summary: String

    public init(modelID: String, displayName: String, summary: String) {
        self.modelID = modelID
        self.displayName = displayName
        self.summary = summary
    }
}

/// Known general-purpose Gemini models used for image understanding and
/// structured prompt extraction. These models return text; image and video
/// generation continue to use their dedicated catalogs.
public enum GeminiAnalysisModelCatalog {
    public static let gemini37Flash = GeminiAnalysisModelDescriptor(
        modelID: "gemini-3.7-flash",
        displayName: "Gemini 3.7 Flash",
        summary: "最新 Flash · 图片理解与结构化分析"
    )

    public static let models = [
        gemini37Flash,
        GeminiAnalysisModelDescriptor(
            modelID: "gemini-3.6-flash",
            displayName: "Gemini 3.6 Flash",
            summary: "稳定 Flash · 多模态理解"
        ),
        GeminiAnalysisModelDescriptor(
            modelID: "gemini-3.5-flash",
            displayName: "Gemini 3.5 Flash",
            summary: "兼容旧项目"
        )
    ]

    public static let defaultModelID = gemini37Flash.modelID

    public static func model(id: String) -> GeminiAnalysisModelDescriptor? {
        models.first { $0.modelID == id }
    }
}
