import Foundation
import LLMKit

/// Google Cloud Vertex AI — Gemini models via a GCP project/location
/// endpoint. The request/response envelope is identical to the public
/// Gemini API (`GeminiProvider`); the only real differences are the URL
/// shape (project + location instead of a flat `models/` path) and
/// authentication (`Authorization: Bearer <token>` instead of
/// `x-goog-api-key`, since Vertex is an IAM-authenticated GCP service, not a
/// simple-API-key one).
///
/// `bearerToken` is a short-lived OAuth2 access token (e.g. from `gcloud
/// auth print-access-token`), not a long-lived API key — it expires
/// (typically after an hour) and the user is responsible for refreshing it
/// in Settings. Full service-account JWT signing/token-refresh is out of
/// scope for a personal, client-only app; this trades convenience for not
/// needing to ship a private key material flow.
nonisolated struct VertexAIProvider: LLMProvider {
    let bearerToken: String
    /// Full path up to and including `.../publishers/google/models/`, e.g.
    /// `https://us-central1-aiplatform.googleapis.com/v1/projects/my-project/locations/us-central1/publishers/google/models/`
    let modelsBaseURL: URL
    let modelID: String
    let session: URLSession

    init(bearerToken: String, modelsBaseURL: URL, modelID: String, session: URLSession = .shared) {
        self.bearerToken = bearerToken
        self.modelsBaseURL = modelsBaseURL
        self.modelID = modelID
        self.session = session
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        var request = URLRequest(url: modelsBaseURL.appending(path: "\(modelID):generateContent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        // Same proto quirk as the public Gemini API: `additionalProperties`
        // in the schema yields a 400 on Vertex's `responseSchema` too.
        let schemaObject = Self.sanitizeSchema(
            try JSONSerialization.jsonObject(with: Data(schema.json.utf8)))
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
            let body = OpenAICompatibleProvider.redactSecrets(
                String(decoding: data.prefix(300), as: UTF8.self))
            throw LLMError.transport("HTTP \(http.statusCode): \(body)")
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

    private static func sanitizeSchema(_ obj: Any) -> Any {
        if let dict = obj as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dict where key != "additionalProperties" {
                out[key] = sanitizeSchema(value)
            }
            return out
        }
        if let array = obj as? [Any] {
            return array.map { sanitizeSchema($0) }
        }
        return obj
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
