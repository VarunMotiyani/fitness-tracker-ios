import Foundation
import LLMKit

/// OpenRouter's OpenAI-compatible chat endpoint. The adapter intentionally
/// keeps the same typed response path as ``OpenAICompatibleProvider`` while
/// adding the attribution headers OpenRouter recommends for applications.
nonisolated struct OpenRouterProvider: LLMProvider {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    static let defaultHTTPReferer = "https://fitness-tracker.app"
    static let defaultXTitle = "Fitness Tracker"

    let inner: OpenAICompatibleProvider

    init(apiKey: String?, modelID: String, session: URLSession = .shared) {
        self.inner = OpenAICompatibleProvider(
            baseURL: Self.baseURL,
            apiKey: apiKey,
            modelID: modelID,
            session: session,
            additionalHeaders: [
                "HTTP-Referer": Self.defaultHTTPReferer,
                "X-Title": Self.defaultXTitle,
            ])
    }

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(structuredOutput: .jsonObject, toolCalling: .viaPrompt)
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        try await inner.complete(system: system, user: user, schema: schema, as: type)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        try await inner.completeWithImage(system: system, user: user, image: image, schema: schema, as: type)
    }

    /// A compact, display-ready model returned by OpenRouter's `/models` API.
    struct Model: Decodable, Hashable, Identifiable, Sendable {
        struct Pricing: Decodable, Hashable, Sendable {
            let prompt: Double
            let completion: Double

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                prompt = try Self.decodeNumber(forKey: .prompt, from: container)
                completion = try Self.decodeNumber(forKey: .completion, from: container)
            }

            private enum CodingKeys: String, CodingKey { case prompt, completion }

            private static func decodeNumber<K: CodingKey>(forKey key: K,
                                                            from container: KeyedDecodingContainer<K>) throws -> Double {
                if let number = try? container.decode(Double.self, forKey: key) { return number }
                if let value = try? container.decode(String.self, forKey: key) { return Double(value) ?? 0 }
                return 0
            }
        }

        let id: String
        let name: String
        let contextLength: Int?
        let pricing: Pricing?

        enum CodingKeys: String, CodingKey {
            case id, name, contextLength = "context_length", pricing
        }

        var promptPrice: Double { pricing?.prompt ?? 0 }
        var completionPrice: Double { pricing?.completion ?? 0 }
    }

    private struct ModelsEnvelope: Decodable { let data: [Model] }
    private actor ModelCache {
        var models: [Model]?

        func set(_ models: [Model]) {
            self.models = models
        }
    }
    private static let modelCache = ModelCache()

    static func decodeModels(_ data: Data) throws -> [Model] {
        try JSONDecoder().decode(ModelsEnvelope.self, from: data).data
    }

    /// Fetches the public model catalogue. Callers should treat this as an
    /// optional enhancement and retain the free-text model field on failure.
    static func fetchModels(session: URLSession = .shared, forceRefresh: Bool = false) async throws -> [Model] {
        if !forceRefresh, let cached = await modelCache.models { return cached }
        var request = URLRequest(url: Self.baseURL.appending(path: "models"))
        request.httpMethod = "GET"
        request.setValue(Self.defaultHTTPReferer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(Self.defaultXTitle, forHTTPHeaderField: "X-Title")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LLMError.transport("OpenRouter model list request failed")
        }
        let models = try decodeModels(data)
        await modelCache.set(models)
        return models
    }
}
