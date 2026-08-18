import Foundation
import ImageLensCore

public struct ProviderImageInput: Equatable, Sendable {
    public var data: Data
    public var mimeType: String
    public var referenceRoles: [GeneratorAssetRole]

    public init(
        data: Data,
        mimeType: String,
        referenceRoles: [GeneratorAssetRole] = []
    ) {
        self.data = data
        self.mimeType = mimeType
        self.referenceRoles = referenceRoles
    }
}

public struct GeneratedImagePayload: Equatable, Sendable {
    public var data: Data
    public var mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public struct GeminiProviderConfiguration: Equatable, Sendable {
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    public static let defaultFilesUploadURL = URL(
        string: "https://generativelanguage.googleapis.com/upload/v1beta/files"
    )!

    public var baseURL: URL
    public var filesUploadURL: URL
    public var analysisModel: String
    public var generationModel: String
    public var includeChinese: Bool

    public init(
        baseURL: URL = Self.defaultBaseURL,
        filesUploadURL: URL? = nil,
        analysisModel: String = GeminiAnalysisModelCatalog.defaultModelID,
        generationModel: String = "gemini-3.1-flash-image",
        includeChinese: Bool = true
    ) {
        self.baseURL = baseURL
        self.filesUploadURL = filesUploadURL ?? Self.filesUploadURL(for: baseURL)
        self.analysisModel = analysisModel
        self.generationModel = generationModel
        self.includeChinese = includeChinese
    }

    private static func filesUploadURL(for baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return defaultFilesUploadURL
        }
        let path = components.path
        if path.hasSuffix("/v1beta") {
            components.path = String(path.dropLast("/v1beta".count)) + "/upload/v1beta/files"
        } else {
            let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = trimmedPath.isEmpty
                ? "/upload/v1beta/files"
                : "/\(trimmedPath)/upload/v1beta/files"
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? defaultFilesUploadURL
    }
}

public protocol ProviderHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse)
}

public extension ProviderHTTPTransport {
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.httpBody = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return try await data(for: request)
    }
}

public actor URLSessionProviderTransport: ProviderHTTPTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 900
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.httpMaximumConnectionsPerHost = 2
            self.session = URLSession(configuration: configuration)
        }
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiProviderError.invalidHTTPResponse
        }
        return (data, httpResponse)
    }

    public func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiProviderError.invalidHTTPResponse
        }
        return (data, httpResponse)
    }
}

public enum GeminiProviderError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case requestTooLarge(Int)
    case unsupportedAspectRatio(modelID: String, aspectRatio: String)
    case unsupportedVideoAspectRatio(modelID: String, aspectRatio: String)
    case unsupportedReferenceMedia(modelID: String, mediaKind: AssetMediaKind)
    case invalidUploadSession
    case fileProcessingFailed(String)
    case fileProcessingTimedOut
    case tooManyReferenceImages(modelID: String, maximum: Int, actual: Int)
    case invalidHTTPResponse
    case httpFailure(statusCode: Int, message: String)
    case emptyResponse
    case malformedResponse(String)
    case noGeneratedImage
    case noGeneratedVideo
    case videoGenerationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let field):
            "Gemini 配置缺少或无法识别：\(field)"
        case .requestTooLarge(let byteCount):
            "图片与提示词请求共 \(byteCount) 字节，超过 Gemini 内联图片 20 MB 上限。"
        case .unsupportedAspectRatio(let modelID, let aspectRatio):
            "\(modelID) 不支持 \(aspectRatio) 图片比例。"
        case .unsupportedVideoAspectRatio(let modelID, let aspectRatio):
            "\(modelID) 不支持 \(aspectRatio) 视频比例。"
        case .unsupportedReferenceMedia(let modelID, let mediaKind):
            "\(modelID) 不支持将\(mediaKind == .video ? "视频" : "这项素材")作为参考。"
        case .invalidUploadSession:
            "Gemini 没有返回可用的视频上传地址。"
        case .fileProcessingFailed(let message):
            "Gemini 处理参考视频失败：\(message)"
        case .fileProcessingTimedOut:
            "Gemini 处理参考视频超时，请稍后重试。"
        case .tooManyReferenceImages(let modelID, let maximum, let actual):
            "\(modelID) 最多支持 \(maximum) 张参考图，当前已连接 \(actual) 张。"
        case .invalidHTTPResponse:
            "Gemini 返回了无法识别的网络响应。"
        case .httpFailure(let statusCode, let message):
            "Gemini 请求失败（HTTP \(statusCode)）：\(message)"
        case .emptyResponse:
            "Gemini 没有返回可用内容。"
        case .malformedResponse(let reason):
            "Gemini 响应无法解析：\(reason)"
        case .noGeneratedImage:
            "Gemini 完成了请求，但没有返回图片。"
        case .noGeneratedVideo:
            "Gemini 完成了请求，但没有返回视频。"
        case .videoGenerationFailed(let message):
            "Gemini 视频生成失败：\(message)"
        }
    }
}

public struct GeminiProviderClient: Sendable {
    private static let inlineRequestLimit = 20 * 1_024 * 1_024

    public var configuration: GeminiProviderConfiguration
    private let transport: any ProviderHTTPTransport

    public init(
        configuration: GeminiProviderConfiguration,
        transport: any ProviderHTTPTransport = URLSessionProviderTransport()
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    public func analyze(image: ProviderImageInput, apiKey: String) async throws -> ReversePromptResponseDTO {
        try validate(apiKey: apiKey, model: configuration.analysisModel)
        let prompt = ReversePromptTemplate(includeChinese: configuration.includeChinese).text
        try validate(image: image)
        try validateInlineSize(estimatedBase64Size(for: image.data.count) + prompt.utf8.count)

        let body = GeminiRequest(
            contents: [
                GeminiContent(parts: [
                    GeminiPart(inlineData: GeminiInlineData(mimeType: image.mimeType, data: image.data.base64EncodedString())),
                    GeminiPart(text: prompt)
                ])
            ],
            generationConfig: GeminiGenerationConfig(
                responseMimeType: "application/json"
            )
        )
        let response = try await send(body, model: configuration.analysisModel, apiKey: apiKey)
        guard let text = response.candidates
            .flatMap(\.content.parts)
            .compactMap(\.text)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw GeminiProviderError.emptyResponse
        }
        guard let data = text.data(using: .utf8) else {
            throw GeminiProviderError.malformedResponse("文本不是 UTF-8")
        }
        return try ReversePromptSchema.decode(data, includeChinese: configuration.includeChinese)
    }

    public func generate(
        prompt: String,
        referenceImages: [ProviderImageInput] = [],
        aspectRatio: String,
        apiKey: String
    ) async throws -> [GeneratedImagePayload] {
        try await generate(
            prompt: prompt,
            referenceMedia: referenceImages.map(\.mediaInput),
            aspectRatio: aspectRatio,
            modelID: configuration.generationModel,
            apiKey: apiKey
        )
    }

    public func generate(
        prompt: String,
        referenceImages: [ProviderImageInput] = [],
        aspectRatio: String,
        modelID: String,
        apiKey: String
    ) async throws -> [GeneratedImagePayload] {
        try await generate(
            prompt: prompt,
            referenceMedia: referenceImages.map(\.mediaInput),
            aspectRatio: aspectRatio,
            modelID: modelID,
            apiKey: apiKey
        )
    }

    public func generate(
        prompt: String,
        referenceMedia: [ProviderMediaInput],
        editInput: ImageEditInput? = nil,
        aspectRatio: String,
        modelID: String,
        apiKey: String
    ) async throws -> [GeneratedImagePayload] {
        try validate(apiKey: apiKey, model: modelID)
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else {
            throw GeminiProviderError.invalidConfiguration("生成提示词")
        }
        for media in referenceMedia { try validate(media: media) }
        if let editInput {
            try validate(editInput: editInput)
        }
        let providerMedia = editInput.map { [$0.source, $0.mask] } ?? []
        let allMedia = providerMedia + referenceMedia
        if let descriptor = ImageGenerationModelCatalog.model(
            providerID: ImageGenerationModelCatalog.geminiProviderID,
            modelID: modelID
        ) {
            guard descriptor.supportedAspectRatios.contains(aspectRatio) else {
                throw GeminiProviderError.unsupportedAspectRatio(
                    modelID: modelID,
                    aspectRatio: aspectRatio
                )
            }
            guard allMedia.count <= descriptor.maxReferenceImages else {
                throw GeminiProviderError.tooManyReferenceImages(
                    modelID: modelID,
                    maximum: descriptor.maxReferenceImages,
                    actual: allMedia.count
                )
            }
            for media in allMedia where !descriptor.supportedReferenceMediaKinds.contains(media.mediaKind) {
                throw GeminiProviderError.unsupportedReferenceMedia(
                    modelID: modelID,
                    mediaKind: media.mediaKind
                )
            }
        }
        let editInstruction = editInput.map(geminiSemanticMaskInstruction(for:))
        let estimatedSize = allMedia.reduce(
            normalizedPrompt.utf8.count + (editInstruction?.utf8.count ?? 0)
        ) { partial, media in
            let inlineSize: Int
            switch media.source {
            case .inline(let data): inlineSize = estimatedBase64Size(for: data.count)
            case .managedFile: inlineSize = 0
            }
            return partial + inlineSize + (media.referenceInstruction?.utf8.count ?? 0)
        }
        try validateInlineSize(estimatedSize)

        var uploadedFiles: [String] = []
        do {
            var parts: [GeminiPart] = []
            if let editInput {
                try await append(
                    editInput.source,
                    to: &parts,
                    uploadedFiles: &uploadedFiles,
                    apiKey: apiKey
                )
                try await append(
                    editInput.mask,
                    to: &parts,
                    uploadedFiles: &uploadedFiles,
                    apiKey: apiKey
                )
                parts.append(GeminiPart(text: geminiSemanticMaskInstruction(for: editInput)))
            }
            for media in referenceMedia {
                try await append(
                    media,
                    to: &parts,
                    uploadedFiles: &uploadedFiles,
                    apiKey: apiKey
                )
                if let instruction = media.referenceInstruction {
                    parts.append(GeminiPart(text: instruction))
                }
            }
            parts.append(GeminiPart(text: normalizedPrompt))
            let body = GeminiRequest(
                contents: [GeminiContent(parts: parts)],
                generationConfig: GeminiGenerationConfig(
                    responseModalities: ["IMAGE"],
                    imageConfig: GeminiImageConfig(aspectRatio: aspectRatio)
                )
            )
            let response = try await send(body, model: modelID, apiKey: apiKey)
            let images = try response.candidates
                .flatMap(\.content.parts)
                .compactMap { part -> GeneratedImagePayload? in
                    guard let inlineData = part.inlineData else { return nil }
                    guard let data = Data(base64Encoded: inlineData.data) else {
                        throw GeminiProviderError.malformedResponse("图片 Base64 无效")
                    }
                    return GeneratedImagePayload(data: data, mimeType: inlineData.mimeType)
                }
            guard !images.isEmpty else { throw GeminiProviderError.noGeneratedImage }
            await deleteUploadedFilesOutsideCancellation(named: uploadedFiles, apiKey: apiKey)
            return images
        } catch {
            await deleteUploadedFilesOutsideCancellation(named: uploadedFiles, apiKey: apiKey)
            throw error
        }
    }

    private func send(_ body: GeminiRequest, model: String, apiKey: String) async throws -> GeminiResponse {
        let endpoint = configuration.baseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("\(model):generateContent", isDirectory: false)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await transport.data(for: request)
        guard (200 ..< 300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data)
            let fallback = String(data: data, encoding: .utf8) ?? "未知错误"
            throw GeminiProviderError.httpFailure(
                statusCode: response.statusCode,
                message: envelope?.error.message ?? fallback
            )
        }
        do {
            return try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw GeminiProviderError.malformedResponse(error.localizedDescription)
        }
    }

    private func uploadAndActivateFile(
        at fileURL: URL,
        mimeType: String,
        apiKey: String
    ) async throws -> GeminiFileResource {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let byteCount = values.fileSize, byteCount > 0 else {
            throw GeminiProviderError.invalidConfiguration("空视频文件")
        }
        guard byteCount <= 2_000_000_000 else {
            throw GeminiProviderError.requestTooLarge(byteCount)
        }

        var startRequest = URLRequest(url: configuration.filesUploadURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue(String(byteCount), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONEncoder().encode(
            GeminiFileStartRequest(file: GeminiFileStartMetadata(displayName: fileURL.lastPathComponent))
        )
        let (startData, startResponse) = try await transport.data(for: startRequest)
        try validateHTTPResponse(startResponse, data: startData)
        guard let uploadURLValue = startResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLValue), uploadURL.scheme == "https" else {
            throw GeminiProviderError.invalidUploadSession
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(String(byteCount), forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (uploadData, uploadResponse) = try await transport.upload(for: uploadRequest, fromFile: fileURL)
        try validateHTTPResponse(uploadResponse, data: uploadData)
        var file = try JSONDecoder().decode(GeminiFileEnvelope.self, from: uploadData).file
        guard !file.name.isEmpty else {
            throw GeminiProviderError.malformedResponse("视频文件缺少 name")
        }

        do {
            var transientFailureCount = 0
            for attempt in 0 ..< 180 {
                try Task.checkCancellation()
                switch file.normalizedState {
                case "ACTIVE":
                    guard !file.uri.isEmpty else {
                        throw GeminiProviderError.malformedResponse("视频文件缺少 uri")
                    }
                    return file
                case "FAILED":
                    throw GeminiProviderError.fileProcessingFailed(file.error?.message ?? "未知错误")
                case "PROCESSING", "STATE_UNSPECIFIED", "":
                    guard attempt < 179 else { throw GeminiProviderError.fileProcessingTimedOut }
                    try await Task.sleep(for: .seconds(5))
                    do {
                        file = try await fetchFile(named: file.name, apiKey: apiKey)
                        transientFailureCount = 0
                    } catch {
                        guard isTransientPollingError(error), transientFailureCount < 3 else {
                            throw error
                        }
                        transientFailureCount += 1
                    }
                default:
                    throw GeminiProviderError.fileProcessingFailed("未知文件状态：\(file.state ?? "nil")")
                }
            }
            throw GeminiProviderError.fileProcessingTimedOut
        } catch {
            await deleteUploadedFilesOutsideCancellation(named: [file.name], apiKey: apiKey)
            throw error
        }
    }

    private func fetchFile(named name: String, apiKey: String) async throws -> GeminiFileResource {
        var request = URLRequest(url: fileResourceURL(named: name))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await transport.data(for: request)
        try validateHTTPResponse(response, data: data)
        return try JSONDecoder().decode(GeminiFileResource.self, from: data)
    }

    private func deleteUploadedFiles(named names: [String], apiKey: String) async {
        for name in names where !name.isEmpty {
            var request = URLRequest(url: fileResourceURL(named: name))
            request.httpMethod = "DELETE"
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            _ = try? await transport.data(for: request)
        }
    }

    private func deleteUploadedFilesOutsideCancellation(named names: [String], apiKey: String) async {
        guard !names.isEmpty else { return }
        let client = self
        await Task.detached(priority: .utility) {
            await client.deleteUploadedFiles(named: names, apiKey: apiKey)
        }.value
    }

    private func isTransientPollingError(_ error: Error) -> Bool {
        if let providerError = error as? GeminiProviderError,
           case .httpFailure(let statusCode, _) = providerError {
            return statusCode == 429 || statusCode >= 500
        }
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .cannotConnectToHost,
                .dnsLookupFailed,
            ].contains(urlError.code)
        }
        return false
    }

    private func validateHTTPResponse(_ response: HTTPURLResponse, data: Data) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data)
            let fallback = String(data: data, encoding: .utf8) ?? "未知错误"
            throw GeminiProviderError.httpFailure(
                statusCode: response.statusCode,
                message: envelope?.error.message ?? fallback
            )
        }
    }

    private func fileResourceURL(named name: String) -> URL {
        name.split(separator: "/").reduce(configuration.baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    private func validate(apiKey: String, model: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiProviderError.invalidConfiguration("API Key")
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiProviderError.invalidConfiguration("模型")
        }
        guard configuration.baseURL.scheme == "https" else {
            throw GeminiProviderError.invalidConfiguration("HTTPS Base URL")
        }
        guard configuration.filesUploadURL.scheme == "https" else {
            throw GeminiProviderError.invalidConfiguration("HTTPS Files Upload URL")
        }
    }

    private func validateInlineSize(_ byteCount: Int) throws {
        guard byteCount < Self.inlineRequestLimit else {
            throw GeminiProviderError.requestTooLarge(byteCount)
        }
    }

    private func validate(image: ProviderImageInput) throws {
        guard !image.data.isEmpty else {
            throw GeminiProviderError.invalidConfiguration("空图片")
        }
        guard image.mimeType.lowercased().hasPrefix("image/") else {
            throw GeminiProviderError.invalidConfiguration("图片 MIME Type")
        }
    }

    private func validate(media: ProviderMediaInput) throws {
        let normalizedMIMEType = media.mimeType.lowercased()
        switch media.mediaKind {
        case .image:
            guard normalizedMIMEType.hasPrefix("image/") else {
                throw GeminiProviderError.invalidConfiguration("图片 MIME Type")
            }
        case .video:
            guard normalizedMIMEType.hasPrefix("video/") else {
                throw GeminiProviderError.invalidConfiguration("视频 MIME Type")
            }
        case .unknown:
            throw GeminiProviderError.invalidConfiguration("参考素材类型")
        }
        switch media.source {
        case .inline(let data):
            guard !data.isEmpty else {
                throw GeminiProviderError.invalidConfiguration("空素材")
            }
        case .managedFile(let url):
            guard url.isFileURL else {
                throw GeminiProviderError.invalidConfiguration("视频文件 URL")
            }
        }
    }

    private func validate(editInput: ImageEditInput) throws {
        guard editInput.mode == .semanticMaskBeta else {
            throw GeminiProviderError.invalidConfiguration("图片编辑模式")
        }
        for media in [editInput.source, editInput.mask] {
            try validate(media: media)
            guard media.mediaKind == .image,
                  media.mimeType.lowercased().hasPrefix("image/") else {
                throw GeminiProviderError.invalidConfiguration("蒙版编辑图片")
            }
        }
        guard editInput.mask.mimeType.lowercased() == "image/png" else {
            throw GeminiProviderError.invalidConfiguration("PNG 蒙版")
        }
    }

    private func append(
        _ media: ProviderMediaInput,
        to parts: inout [GeminiPart],
        uploadedFiles: inout [String],
        apiKey: String
    ) async throws {
        switch media.source {
        case .inline(let data):
            parts.append(
                GeminiPart(
                    inlineData: GeminiInlineData(
                        mimeType: media.mimeType,
                        data: data.base64EncodedString()
                    )
                )
            )
        case .managedFile(let fileURL):
            let file = try await uploadAndActivateFile(
                at: fileURL,
                mimeType: media.mimeType,
                apiKey: apiKey
            )
            uploadedFiles.append(file.name)
            parts.append(
                GeminiPart(
                    fileData: GeminiFileData(
                        mimeType: file.mimeType ?? media.mimeType,
                        fileUri: file.uri
                    ),
                    videoMetadata: media.mediaKind == .video
                        ? GeminiVideoMetadata(fps: 0.5)
                        : nil
                )
            )
        }
    }

    private func geminiSemanticMaskInstruction(for editInput: ImageEditInput) -> String {
        """
        [Image Lens semantic-mask edit beta]
        The first image is the source image. The second image is a same-size PNG mask: white marks the requested edit region and black marks protected content. Apply the user's edit only inside the white region and preserve content outside it as closely as possible. Gemini does not provide a native pixel-locked mask API, so treat this as semantic guidance rather than an exact compositing boundary.
        """
    }

    private func estimatedBase64Size(for byteCount: Int) -> Int {
        ((byteCount + 2) / 3) * 4
    }
}

private extension ProviderImageInput {
    var mediaInput: ProviderMediaInput {
        ProviderMediaInput(
            source: .inline(data),
            mimeType: mimeType,
            mediaKind: .image,
            referenceRoles: referenceRoles
        )
    }
}

private extension ProviderMediaInput {
    var referenceInstruction: String? {
        let labels = referenceRoles.map(\.geminiReferenceLabel)
        guard !labels.isEmpty else { return nil }
        let noun = mediaKind == .video ? "参考视频" : "参考图"
        return "下面这项\(noun)用于：\(labels.joined(separator: "、"))。请只提取这些维度作为生成参考。"
    }
}

private extension GeneratorAssetRole {
    var geminiReferenceLabel: String {
        switch self {
        case .general: "整体视觉参考"
        case .identity: "主体与外观"
        case .environment: "场景与环境"
        case .style: "视觉风格"
        case .composition: "画面构图"
        case .palette: "色彩与配色"
        case .structure: "空间结构"
        }
    }
}

extension GeminiProviderClient: ImageGenerationProvider {
    public var providerID: ProviderID { ImageGenerationModelCatalog.geminiProviderID }

    public func generate(
        request: ImageGenerationRequest,
        credential: String
    ) async throws -> [GeneratedImagePayload] {
        guard request.target.providerID == providerID else {
            throw GeminiProviderError.invalidConfiguration("生图服务")
        }
        return try await generate(
            prompt: request.prompt,
            referenceMedia: request.referenceMedia,
            editInput: request.editInput,
            aspectRatio: request.aspectRatio,
            modelID: request.target.modelID,
            apiKey: credential
        )
    }
}

extension GeminiProviderClient: VideoGenerationProvider {
    public func generate(
        request: VideoGenerationRequest,
        credential: String
    ) async throws -> [GeneratedVideoPayload] {
        guard request.target.providerID == providerID else {
            throw GeminiProviderError.invalidConfiguration("视频生成服务")
        }
        try validate(apiKey: credential, model: request.target.modelID)

        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw GeminiProviderError.invalidConfiguration("视频生成提示词")
        }
        guard let descriptor = VideoGenerationModelCatalog.model(
            providerID: request.target.providerID,
            modelID: request.target.modelID
        ) else {
            throw GeminiProviderError.invalidConfiguration("视频生成模型")
        }
        guard descriptor.supportedAspectRatios.contains(request.aspectRatio) else {
            throw GeminiProviderError.unsupportedVideoAspectRatio(
                modelID: request.target.modelID,
                aspectRatio: request.aspectRatio
            )
        }
        let durationSeconds: Int
        if let rawDuration = request.providerOptions[
            GenerationParameters.videoDurationProviderOptionKey
        ] {
            guard let requestedDuration = Int(rawDuration),
                  GenerationParameters.supportedVideoDurationSeconds.contains(requestedDuration) else {
                throw GeminiProviderError.invalidConfiguration("视频时长（仅支持 3–10 秒）")
            }
            durationSeconds = requestedDuration
        } else {
            durationSeconds = GenerationParameters.defaultVideoDurationSeconds
        }
        guard request.referenceMedia.count <= descriptor.maxReferenceImages else {
            throw GeminiProviderError.tooManyReferenceImages(
                modelID: request.target.modelID,
                maximum: descriptor.maxReferenceImages,
                actual: request.referenceMedia.count
            )
        }

        var inputItems: [GeminiOmniInputItem] = []
        var estimatedSize = prompt.utf8.count
        for media in request.referenceMedia {
            guard media.mediaKind == .image else {
                throw GeminiProviderError.unsupportedReferenceMedia(
                    modelID: request.target.modelID,
                    mediaKind: media.mediaKind
                )
            }
            guard media.mimeType.lowercased().hasPrefix("image/") else {
                throw GeminiProviderError.invalidConfiguration("图片 MIME Type")
            }
            guard case .inline(let data) = media.source else {
                throw GeminiProviderError.invalidConfiguration("视频参考图必须使用内联数据")
            }
            guard !data.isEmpty else {
                throw GeminiProviderError.invalidConfiguration("空参考图")
            }
            estimatedSize += estimatedBase64Size(for: data.count)
            inputItems.append(
                GeminiOmniInputItem(
                    type: "image",
                    data: data.base64EncodedString(),
                    mimeType: media.mimeType
                )
            )
        }
        try validateInlineSize(estimatedSize)

        let input: GeminiOmniInput
        if inputItems.isEmpty {
            input = .text(prompt)
        } else {
            inputItems.append(GeminiOmniInputItem(type: "text", text: prompt))
            input = .items(inputItems)
        }
        let body = GeminiOmniInteractionRequest(
            model: request.target.modelID,
            input: input,
            responseFormat: GeminiOmniResponseFormat(
                type: "video",
                aspectRatio: request.aspectRatio,
                delivery: "inline",
                duration: "\(durationSeconds)s"
            )
        )
        let endpoint = configuration.baseURL.appendingPathComponent("interactions")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(credential, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await transport.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let interaction: GeminiOmniInteractionResponse
        do {
            interaction = try JSONDecoder().decode(GeminiOmniInteractionResponse.self, from: data)
        } catch {
            throw GeminiProviderError.malformedResponse(Self.omniDecodeFailureReason(error, data: data))
        }
        if let failure = interaction.failureMessage {
            throw GeminiProviderError.videoGenerationFailed(failure)
        }
        var videos = try (interaction.steps ?? [])
            .filter { $0.type == "model_output" }
            .flatMap { $0.content ?? [] }
            .compactMap { content -> GeneratedVideoPayload? in
                guard content.type == "video", let encoded = content.data else { return nil }
                guard let videoData = Data(base64Encoded: encoded) else {
                    throw GeminiProviderError.malformedResponse("视频 Base64 无效")
                }
                return GeneratedVideoPayload(
                    data: videoData,
                    mimeType: content.mimeType ?? "video/mp4"
                )
            }
        if videos.isEmpty,
           let encoded = interaction.outputVideo?.data {
            guard let videoData = Data(base64Encoded: encoded) else {
                throw GeminiProviderError.malformedResponse("视频 Base64 无效")
            }
            videos = [GeneratedVideoPayload(
                data: videoData,
                mimeType: interaction.outputVideo?.mimeType ?? "video/mp4"
            )]
        }
        if let remoteURI = (interaction.steps ?? [])
            .filter({ $0.type == "model_output" })
            .flatMap({ $0.content ?? [] })
            .compactMap(\.uri)
            .first ?? interaction.outputVideo?.uri {
            throw GeminiProviderError.videoGenerationFailed(
                "服务返回了远程视频地址（\(remoteURI)），当前版本要求内联视频，请重试。"
            )
        }
        guard !videos.isEmpty else { throw GeminiProviderError.noGeneratedVideo }
        return videos
    }

    private static func omniDecodeFailureReason(_ error: Error, data: Data) -> String {
        let codingPath: String
        switch error {
        case DecodingError.keyNotFound(_, let context),
             DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context),
             DecodingError.dataCorrupted(let context):
            codingPath = context.codingPath.map(\.stringValue).joined(separator: ".")
        default:
            codingPath = ""
        }
        let rootKeys = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?
            .keys.sorted().joined(separator: ", ") ?? "无法读取"
        let location = codingPath.isEmpty ? "根对象" : codingPath
        return "Interactions 响应结构不兼容（位置：\(location)；顶层字段：\(rootKeys)）"
    }
}

private struct GeminiOmniInteractionRequest: Encodable {
    var model: String
    var input: GeminiOmniInput
    var responseFormat: GeminiOmniResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case responseFormat = "response_format"
    }
}

private enum GeminiOmniInput: Encodable {
    case text(String)
    case items([GeminiOmniInputItem])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .items(let items): try container.encode(items)
        }
    }
}

private struct GeminiOmniInputItem: Encodable {
    var type: String
    var data: String?
    var mimeType: String?
    var text: String?

    init(type: String, data: String? = nil, mimeType: String? = nil, text: String? = nil) {
        self.type = type
        self.data = data
        self.mimeType = mimeType
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case type
        case data
        case mimeType = "mime_type"
        case text
    }
}

private struct GeminiOmniResponseFormat: Encodable {
    var type: String
    var aspectRatio: String
    var delivery: String
    var duration: String

    enum CodingKeys: String, CodingKey {
        case type
        case aspectRatio = "aspect_ratio"
        case delivery
        case duration
    }
}

private struct GeminiOmniInteractionResponse: Decodable {
    var status: String?
    var steps: [GeminiOmniStep]?
    var error: GeminiOmniStatus?
    var outputVideo: GeminiOmniContent?

    enum CodingKeys: String, CodingKey {
        case status
        case steps
        case error
        case outputVideo = "output_video"
    }

    var failureMessage: String? {
        if let message = error?.message, !message.isEmpty { return message }
        if let message = steps?.compactMap(\.error?.message).first(where: { !$0.isEmpty }) {
            return message
        }
        if let status {
            switch status.lowercased() {
            case "completed": return nil
            case "queued", "in_progress": return "请求尚未完成（状态：\(status)），请稍后重试。"
            case "requires_action": return "请求需要额外操作，当前版本暂不支持。"
            default: return "请求状态为 \(status)"
            }
        }
        return nil
    }
}

private struct GeminiOmniStep: Decodable {
    var type: String
    var content: [GeminiOmniContent]?
    var error: GeminiOmniStatus?
}

private struct GeminiOmniStatus: Decodable {
    var message: String?
}

private struct GeminiOmniContent: Decodable {
    var type: String
    var mimeType: String?
    var data: String?
    var uri: String?

    enum CodingKeys: String, CodingKey {
        case type
        case mimeType = "mime_type"
        case data
        case uri
    }
}

private struct GeminiRequest: Encodable {
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig?
}

private struct GeminiContent: Codable {
    var parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    var text: String?
    var inlineData: GeminiInlineData?
    var fileData: GeminiFileData?
    var videoMetadata: GeminiVideoMetadata?

    init(
        text: String? = nil,
        inlineData: GeminiInlineData? = nil,
        fileData: GeminiFileData? = nil,
        videoMetadata: GeminiVideoMetadata? = nil
    ) {
        self.text = text
        self.inlineData = inlineData
        self.fileData = fileData
        self.videoMetadata = videoMetadata
    }
}

private struct GeminiInlineData: Codable {
    var mimeType: String
    var data: String
}

private struct GeminiFileData: Codable {
    var mimeType: String
    var fileUri: String
}

private struct GeminiVideoMetadata: Codable {
    var fps: Double
}

private struct GeminiFileStartRequest: Encodable {
    var file: GeminiFileStartMetadata
}

private struct GeminiFileStartMetadata: Encodable {
    var displayName: String
}

private struct GeminiFileEnvelope: Decodable {
    var file: GeminiFileResource
}

private struct GeminiFileResource: Decodable {
    struct FileError: Decodable {
        var message: String?
    }

    var name: String
    var uri: String
    var mimeType: String?
    var state: String?
    var error: FileError?

    var normalizedState: String {
        state?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case uri
        case mimeType
        case state
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? ""
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        error = try container.decodeIfPresent(FileError.self, forKey: .error)
    }
}

private struct GeminiGenerationConfig: Encodable {
    var responseMimeType: String?
    var responseModalities: [String]?
    var imageConfig: GeminiImageConfig?

    init(
        responseMimeType: String? = nil,
        responseModalities: [String]? = nil,
        imageConfig: GeminiImageConfig? = nil
    ) {
        self.responseMimeType = responseMimeType
        self.responseModalities = responseModalities
        self.imageConfig = imageConfig
    }
}

private struct GeminiImageConfig: Codable {
    var aspectRatio: String
}

private struct GeminiResponse: Decodable {
    var candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    var content: GeminiContent
}

private struct GeminiErrorEnvelope: Decodable {
    var error: GeminiErrorBody
}

private struct GeminiErrorBody: Decodable {
    var message: String
}
