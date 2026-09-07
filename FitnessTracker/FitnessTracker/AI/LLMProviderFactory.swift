import Foundation
import LLMKit

nonisolated enum LLMProviderFactory {
    enum FactoryError: Error, Equatable {
        case missingBaseURL, missingAPIKey, invalidBaseURL, missingRegion, malformedCredentials
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
        case .openRouter:
            return OpenRouterProvider(apiKey: apiKey, modelID: modelID, session: session)
        case .gemini:
            guard let apiKey, !apiKey.isEmpty else { throw FactoryError.missingAPIKey }
            return GeminiProvider(apiKey: apiKey, modelID: modelID, session: session)
        case .appleOnDevice:
            return FoundationModelsProvider()
        case .vertexAI:
            guard let baseURL,
                  let url = URL(string: baseURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https",
                  url.host != nil
            else { throw FactoryError.invalidBaseURL }
            guard let apiKey, !apiKey.isEmpty else { throw FactoryError.missingAPIKey }
            return VertexAIProvider(bearerToken: apiKey, modelsBaseURL: url, modelID: modelID, session: session)
        case .bedrock:
            guard let baseURL, !baseURL.isEmpty else { throw FactoryError.missingRegion }
            guard let apiKey, !apiKey.isEmpty else { throw FactoryError.missingAPIKey }
            guard let credentials = BedrockProvider.parseCredentials(apiKey) else {
                throw FactoryError.malformedCredentials
            }
            return BedrockProvider(
                accessKeyId: credentials.accessKeyId, secretAccessKey: credentials.secretAccessKey,
                sessionToken: credentials.sessionToken, region: baseURL, modelID: modelID, session: session)
        }
    }

    @MainActor
    static func make(from profile: ProviderProfile,
                     fallback: ProviderProfile? = nil,
                     session: URLSession? = nil) throws -> any LLMProvider {
        let base = try makeRaw(from: profile, session: session)
        // A fallback that itself can't be built (bad config) is dropped, not fatal.
        let fb = fallback.flatMap { try? makeRaw(from: $0, session: session) }
        // Every production provider gets bounded retry on transient failures,
        // plus one-shot failover when a fallback profile is configured.
        return ResilientProvider(wrapped: base, fallback: fb)
    }

    @MainActor
    private static func makeRaw(from profile: ProviderProfile, session: URLSession?) throws -> any LLMProvider {
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
