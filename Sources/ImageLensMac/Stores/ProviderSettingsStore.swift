import Foundation
import ImageLensPersistence
import ImageLensProviders
import Observation

@MainActor
@Observable
final class ProviderSettingsStore {
    static let shared = ProviderSettingsStore()
    static let credentialAccount = "gemini.api-key"

    var baseURLString: String
    var analysisModel: String
    var generationModel: String
    var includeChinese: Bool
    var apiKey = ""
    private(set) var isCredentialLoaded = false
    private(set) var statusMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let credentials: any CredentialStore

    init(
        defaults: UserDefaults = .standard,
        credentials: any CredentialStore = KeychainCredentialStore()
    ) {
        self.defaults = defaults
        self.credentials = credentials
        baseURLString = defaults.string(forKey: Keys.baseURL)
            ?? GeminiProviderConfiguration.defaultBaseURL.absoluteString
        analysisModel = defaults.string(forKey: Keys.analysisModel)
            ?? GeminiAnalysisModelCatalog.defaultModelID
        generationModel = defaults.string(forKey: Keys.generationModel)
            ?? ImageGenerationModelCatalog.gemini.defaultModelID
        includeChinese = defaults.object(forKey: Keys.includeChinese) as? Bool ?? true
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var configuration: GeminiProviderConfiguration? {
        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              baseURL.scheme == "https" else { return nil }
        return GeminiProviderConfiguration(
            baseURL: baseURL,
            analysisModel: analysisModel.trimmingCharacters(in: .whitespacesAndNewlines),
            generationModel: generationModel.trimmingCharacters(in: .whitespacesAndNewlines),
            includeChinese: includeChinese
        )
    }

    func loadCredentialIfNeeded() async {
        guard !isCredentialLoaded else { return }
        do {
            apiKey = try await credentials.value(for: Self.credentialAccount) ?? ""
        } catch {
            statusMessage = error.localizedDescription
        }
        isCredentialLoaded = true
    }

    func save() async throws {
        guard configuration != nil else {
            throw GeminiProviderError.invalidConfiguration("HTTPS Base URL")
        }
        defaults.set(baseURLString, forKey: Keys.baseURL)
        defaults.set(analysisModel, forKey: Keys.analysisModel)
        defaults.set(generationModel, forKey: Keys.generationModel)
        defaults.set(includeChinese, forKey: Keys.includeChinese)
        try await credentials.setValue(
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            for: Self.credentialAccount
        )
        statusMessage = "服务设置已保存；API Key 仅存储在 macOS 钥匙串。"
    }

    private enum Keys {
        static let baseURL = "provider.gemini.baseURL"
        static let analysisModel = "provider.gemini.analysisModel"
        static let generationModel = "provider.gemini.generationModel"
        static let includeChinese = "provider.gemini.includeChinese"
    }
}
