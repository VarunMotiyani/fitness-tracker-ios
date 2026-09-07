import Foundation
import LLMKit

nonisolated struct OpenAICompatibleProvider: LLMProvider {
    let baseURL: URL
    let apiKey: String?
    let modelID: String
    let session: URLSession
    let additionalHeaders: [String: String]

    init(baseURL: URL, apiKey: String?, modelID: String, session: URLSession = .shared,
         additionalHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
        self.additionalHeaders = additionalHeaders
    }

    var capabilities: ProviderCapabilities { .openAICompatibleDefault(host: baseURL.host) }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        // Mode comes from the declared capability, not a per-request guess at
        // the schema's shape: `api.openai.com` enforces strict `json_schema`,
        // every other OpenAI-compatible endpoint (Groq, Together, …) is only
        // trusted for `json_object`.
        let schemaObject = try? JSONSerialization.jsonObject(with: Data(schema.json.utf8))
        let usesJSONMode = capabilities.structuredOutput != .nativeJSONSchema
        let responseFormat: [String: Any] = usesJSONMode
            ? ["type": "json_object"]
            : [
                "type": "json_schema",
                "json_schema": ["name": "response", "strict": true, "schema": schemaObject as Any],
            ]
        let systemPrompt = usesJSONMode
            ? system + "\n\nReturn a valid JSON object only."
            : system
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": user],
            ],
            "response_format": responseFormat,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("no HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            let body = Self.redactSecrets(String(decoding: data.prefix(300), as: UTF8.self))
            throw LLMError.transport("HTTP \(http.statusCode): \(body)")
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw LLMError.decoding("envelope: \(error)") }
        guard let content = envelope.choices.first?.message.content else { throw LLMError.emptyResponse }

        let value: Value
        do { value = try JSONDecoder().decode(Value.self, from: Data(content.utf8)) }
        catch { throw LLMError.decoding("content: \(error)") }

        return LLMResult(value: value,
                         inputTokens: envelope.usage?.prompt_tokens ?? 0,
                         outputTokens: envelope.usage?.completion_tokens ?? 0,
                         cachedTokens: envelope.usage?.prompt_tokens_details?.cached_tokens ?? 0,
                         rawJSON: content)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }

    /// Strips anything shaped like an OpenAI (`sk-…`) or Google (`AIza…`) key from
    /// a provider error body before it goes into an `LLMError` string.
    static func redactSecrets(_ text: String) -> String {
        text.replacing(/sk-[A-Za-z0-9_-]{8,}/, with: "«redacted»")
            .replacing(/AIza[A-Za-z0-9_-]{8,}/, with: "«redacted»")
    }

    private struct Envelope: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        struct Usage: Decodable {
            struct Details: Decodable { let cached_tokens: Int? }
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let prompt_tokens_details: Details?
        }
        let choices: [Choice]
        let usage: Usage?
    }
}
