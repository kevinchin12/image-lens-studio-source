import Foundation
import ImageLensCore

public struct VideoGenerationRequest: Equatable, Sendable {
    public var target: CompileTarget
    public var prompt: String
    public var referenceMedia: [ProviderMediaInput]
    public var aspectRatio: String
    public var providerOptions: [String: String]

    public init(
        target: CompileTarget,
        prompt: String,
        referenceMedia: [ProviderMediaInput] = [],
        aspectRatio: String,
        providerOptions: [String: String] = [:]
    ) {
        self.target = target
        self.prompt = prompt
        self.referenceMedia = referenceMedia
        self.aspectRatio = aspectRatio
        self.providerOptions = providerOptions
    }
}

public struct GeneratedVideoPayload: Equatable, Sendable {
    public var data: Data
    public var mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public protocol VideoGenerationProvider: Sendable {
    var providerID: ProviderID { get }

    func generate(
        request: VideoGenerationRequest,
        credential: String
    ) async throws -> [GeneratedVideoPayload]
}
