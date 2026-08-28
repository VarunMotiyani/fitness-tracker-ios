import Foundation
import LLMKit

nonisolated enum LLMProviderFactory {
    enum FactoryError: Error, Equatable {
        case missingBaseURL, missingAPIKey, invalidBaseURL
    }

    static func make(kind: AdapterKind, baseURL: String?, apiKey: String?,
                     modelID: String, session: URLSession? = nil) throws -> any LLMProvider {
        let session = session ?? defaultSession()
        switch kind {
        case .openAICompatible:
            guard let baseURL,
                  let url = URL(string: baseURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  url.host != nil
            else { throw FactoryError.invalidBaseURL }
            return OpenAICompatibleProvider(baseURL: url, apiKey: apiKey, modelID: modelID, session: session)
        case .gemini:
            guard let apiKey, !apiKey.isEmpty else { throw FactoryError.missingAPIKey }
            return GeminiProvider(apiKey: apiKey, modelID: modelID, session: session)
        case .appleOnDevice:
            return FoundationModelsProvider()
        }
    }

    @MainActor
    static func make(from profile: ProviderProfile, session: URLSession? = nil) throws -> any LLMProvider {
        let key = profile.apiKeyRef.flatMap { try? KeychainStore.get(account: $0) } ?? nil
        return try make(kind: profile.adapterKind, baseURL: profile.baseURL,
                        apiKey: key, modelID: profile.modelID, session: session)
    }

    /// A dedicated ephemeral session for LLM calls: no shared on-disk cache,
    /// and a request timeout that survives a slow reasoning model.
    private static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }
}
