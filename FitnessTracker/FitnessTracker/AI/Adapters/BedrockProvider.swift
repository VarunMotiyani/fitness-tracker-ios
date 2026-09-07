import Foundation
import LLMKit

/// AWS Bedrock, via the model-agnostic Converse API
/// (`POST /model/{modelId}/converse`) — works the same way regardless of
/// which underlying model (Claude, Llama, Titan, Mistral, ...) is hosted
/// behind it. Every request is signed with AWS SigV4 (`AWSSigV4Signer`),
/// since Bedrock is IAM-authenticated, not API-key-authenticated.
///
/// The Converse API's structured-output support varies by underlying model,
/// so — unlike `OpenAICompatibleProvider`'s strict `response_format` or
/// Gemini's `responseSchema` — the JSON schema is enforced by instruction
/// (embedded in the system prompt) rather than a provider-level contract.
/// This is strictly weaker than the other two adapters and is a known,
/// accepted trade-off for working generically across any Bedrock-hosted
/// model rather than one specific model family's tool-use format.
nonisolated struct BedrockProvider: LLMProvider {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
    let region: String
    let modelID: String
    let session: URLSession

    init(accessKeyId: String, secretAccessKey: String, sessionToken: String?,
         region: String, modelID: String, session: URLSession = .shared) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.region = region
        self.modelID = modelID
        self.session = session
    }

    /// Parses the composite secret `ProviderProfile.apiKeyRef` stores for
    /// this adapter kind: `{"accessKeyId":"...","secretAccessKey":"...","sessionToken":"..."}`
    /// (`sessionToken` optional). Returns `nil` on malformed JSON so the
    /// factory can surface `FactoryError.missingAPIKey` instead of crashing.
    static func parseCredentials(_ json: String) -> (accessKeyId: String, secretAccessKey: String, sessionToken: String?)? {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(BedrockCredentials.self, from: data)
        else { return nil }
        return (decoded.accessKeyId, decoded.secretAccessKey, decoded.sessionToken)
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        let host = "bedrock-runtime.\(region).amazonaws.com"
        guard let url = URL(string: "https://\(host)/model/\(modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID)/converse") else {
            throw LLMError.transport("invalid Bedrock URL for model '\(modelID)'")
        }

        let schemaInstruction = "\(system)\n\nRespond only with JSON matching this exact schema, no other text:\n\(schema.json)"
        let body: [String: Any] = [
            "system": [["text": schemaInstruction]],
            "messages": [["role": "user", "content": [["text": user]]]],
            "inferenceConfig": ["temperature": 0.2],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        request = AWSSigV4Signer.sign(
            request: request, body: bodyData,
            accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken,
            region: region, service: "bedrock"
        )

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
        guard let text = envelope.output.message.content.first?.text else {
            throw LLMError.emptyResponse
        }
        // The model may wrap its JSON in a fenced code block despite the
        // instruction not to — strip a leading/trailing ``` fence if present,
        // since Bedrock's structured-output enforcement is instruction-only
        // (see the type doc comment) and some models do this anyway.
        let cleaned = Self.stripCodeFence(text)

        let value: Value
        do { value = try JSONDecoder().decode(Value.self, from: Data(cleaned.utf8)) }
        catch { throw LLMError.decoding("text: \(error)") }

        return LLMResult(value: value,
                         inputTokens: envelope.usage?.inputTokens ?? 0,
                         outputTokens: envelope.usage?.outputTokens ?? 0,
                         cachedTokens: 0,
                         rawJSON: cleaned)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }

    static func stripCodeFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        trimmed.removeFirst(3)
        if let newlineIdx = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: newlineIdx)...])
        }
        if trimmed.hasSuffix("```") {
            trimmed.removeLast(3)
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct BedrockCredentials: Decodable {
        let accessKeyId: String
        let secretAccessKey: String
        let sessionToken: String?
    }

    private struct Envelope: Decodable {
        struct Output: Decodable {
            struct Message: Decodable {
                struct Content: Decodable { let text: String? }
                let content: [Content]
            }
            let message: Message
        }
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
        }
        let output: Output
        let usage: Usage?
    }
}
