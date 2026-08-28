import Foundation
import LLMKit

nonisolated struct GeminiProvider: LLMProvider {
    let apiKey: String
    let modelID: String
    let session: URLSession
    let baseURL: URL

    init(apiKey: String, modelID: String, session: URLSession = .shared,
         baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
        self.baseURL = baseURL
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        var request = URLRequest(url: baseURL.appending(path: "models/\(modelID):generateContent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let schemaObject = try JSONSerialization.jsonObject(with: Data(schema.json.utf8))
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schemaObject,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw LLMError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("no HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            throw LLMError.transport("HTTP \(http.statusCode): \(String(decoding: data.prefix(300), as: UTF8.self))")
        }

        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw LLMError.decoding("envelope: \(error)") }
        guard let text = envelope.candidates.first?.content.parts.first?.text else {
            throw LLMError.emptyResponse
        }
        let value: Value
        do { value = try JSONDecoder().decode(Value.self, from: Data(text.utf8)) }
        catch { throw LLMError.decoding("text: \(error)") }

        return LLMResult(value: value,
                         inputTokens: envelope.usageMetadata?.promptTokenCount ?? 0,
                         outputTokens: envelope.usageMetadata?.candidatesTokenCount ?? 0,
                         cachedTokens: envelope.usageMetadata?.cachedContentTokenCount ?? 0,
                         rawJSON: text)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }

    private struct Envelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable { struct Part: Decodable { let text: String }; let parts: [Part] }
            let content: Content
        }
        struct Usage: Decodable {
            let promptTokenCount: Int?
            let candidatesTokenCount: Int?
            let cachedContentTokenCount: Int?
        }
        let candidates: [Candidate]
        let usageMetadata: Usage?
    }
}
