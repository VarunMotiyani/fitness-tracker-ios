import Foundation
import LLMKit

nonisolated struct OpenAICompatibleProvider: LLMProvider {
    let baseURL: URL
    let apiKey: String?
    let modelID: String
    let session: URLSession

    init(baseURL: URL, apiKey: String?, modelID: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }

        let schemaObject = try JSONSerialization.jsonObject(with: Data(schema.json.utf8))
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "plan", "strict": true, "schema": schemaObject],
            ],
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
            throw LLMError.transport("HTTP \(http.statusCode): \(String(decoding: data.prefix(300), as: UTF8.self))")
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
