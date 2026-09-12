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

    var capabilities: ProviderCapabilities { .googleResponseSchema.overriding(toolCalling: .native) }

    private func send(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: modelsBaseURL.appending(path: "\(modelID):generateContent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
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
        return data
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        // Same proto quirk as the public Gemini API: `additionalProperties`
        // in the schema yields a 400 on Vertex's `responseSchema` too.
        let schemaObject = GeminiProvider.normalizeSchema(
            try JSONSerialization.jsonObject(with: Data(schema.json.utf8)))
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schemaObject,
                "thinkingConfig": ["thinkingLevel": "low"],
            ],
        ]
        let data = try await send(body: body)

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
        let schemaObject = GeminiProvider.normalizeSchema(
            try JSONSerialization.jsonObject(with: Data(schema.json.utf8)))
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": user],
                    ["inlineData": ["mimeType": image.mimeType, "data": image.data.base64EncodedString()]],
                ],
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schemaObject,
                "thinkingConfig": ["thinkingLevel": "low"],
            ],
        ]
        let data = try await send(body: body)
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

    func completeToolTurn<Final: Decodable & Sendable>(
        system: String,
        messages: [ToolChatMessage],
        tools: [ToolDescriptor],
        finalSchema: JSONSchema,
        as type: Final.Type
    ) async throws -> NativeToolTurnResult<Final> {
        var contents: [[String: Any]] = []
        for message in messages {
            switch message.role {
            case .system:
                continue
            case .user:
                contents.append(["role": "user", "parts": [["text": message.content ?? ""]]])
            case .assistant:
                if let calls = message.toolCalls, !calls.isEmpty {
                    contents.append(["role": "model", "parts": calls.map { call -> [String: Any] in
                        let args = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) ?? [String: Any]()
                        var functionCall: [String: Any] = ["name": call.name, "args": args]
                        if !call.id.isEmpty { functionCall["id"] = call.id }
                        var part: [String: Any] = ["functionCall": functionCall]
                        if let signature = call.thoughtSignature { part["thoughtSignature"] = signature }
                        return part
                    }])
                } else {
                    contents.append(["role": "model", "parts": [["text": message.content ?? ""]]])
                }
            case .tool:
                let responseObject = (try? JSONSerialization.jsonObject(with: Data((message.content ?? "{}").utf8)))
                    ?? ["result": message.content ?? ""]
                var functionResponse: [String: Any] = [
                    "name": message.toolName ?? message.toolCallID ?? "",
                    "response": responseObject,
                ]
                if let id = message.toolCallID, !id.isEmpty { functionResponse["id"] = id }
                contents.append(["role": "user", "parts": [["functionResponse": functionResponse]]])
            }
        }

        let wireTools: [[String: Any]] = tools.map { tool in
            let schemaObject = (try? GeminiProvider.normalizeSchema(
                JSONSerialization.jsonObject(with: Data(tool.argsSchemaJSON.utf8)), uppercaseTypes: false))
                ?? ["type": "object"]
            return ["name": tool.name, "description": tool.description, "parameters": schemaObject]
        }
        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": system + "\n\nWhen you are finished calling tools, reply with a JSON object matching: " + finalSchema.json]]],
            "contents": contents,
            "generationConfig": ["thinkingConfig": ["thinkingLevel": "low"]],
        ]
        if !wireTools.isEmpty {
            body["tools"] = [["functionDeclarations": wireTools]]
            body["toolConfig"] = ["functionCallingConfig": ["mode": "AUTO"]]
        } else {
            body["generationConfig"] = [
                "responseMimeType": "application/json",
                "responseSchema": (try? GeminiProvider.normalizeSchema(
                    JSONSerialization.jsonObject(with: Data(finalSchema.json.utf8)))) ?? [String: Any](),
                "thinkingConfig": ["thinkingLevel": "low"],
            ]
        }
        let data = try await send(body: body)
        let envelope: ToolEnvelope
        do { envelope = try JSONDecoder().decode(ToolEnvelope.self, from: data) }
        catch { throw LLMError.decoding("tool envelope: \(error)") }
        guard let parts = envelope.candidates.first?.content.parts else { throw LLMError.emptyResponse }
        let functionCalls = parts.compactMap { part in
            part.functionCall.map { ($0, part.thoughtSignature) }
        }
        let turn: NativeToolTurn<Final>
        if !functionCalls.isEmpty {
            turn = .toolCalls(functionCalls.map { call, signature in
                let args = call.args?.reduce(into: [String: Any]()) { result, entry in
                    result[entry.key] = entry.value.value
                } ?? [:]
                let argsJSON = (try? JSONSerialization.data(withJSONObject: args))
                    .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                return NativeToolCall(id: call.id ?? "", name: call.name,
                                      argumentsJSON: argsJSON, thoughtSignature: signature)
            })
        } else if let text = parts.compactMap(\.text).first {
            do { turn = .final(try OpenAICompatibleProvider.decodeFinal(Final.self, from: text)) }
            catch { throw LLMError.decoding("final content: \(error)") }
        } else {
            throw LLMError.emptyResponse
        }
        return NativeToolTurnResult(
            turn: turn,
            inputTokens: envelope.usageMetadata?.promptTokenCount ?? 0,
            outputTokens: envelope.usageMetadata?.candidatesTokenCount ?? 0,
            cachedTokens: envelope.usageMetadata?.cachedContentTokenCount ?? 0)
    }

    private struct Envelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String; let thoughtSignature: String? }
                let parts: [Part]
            }
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

    private struct ToolEnvelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable { let parts: [Part] }
            let content: Content
        }
        struct Part: Decodable {
            struct FunctionCall: Decodable {
                let name: String
                let id: String?
                let args: [String: VertexAnyDecodableValue]?
            }
            let text: String?
            let functionCall: FunctionCall?
            let thoughtSignature: String?
        }
        let candidates: [Candidate]
        let usageMetadata: Envelope.Usage?
    }
}

private nonisolated struct VertexAnyDecodableValue: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([String: VertexAnyDecodableValue].self) {
            value = v.reduce(into: [String: Any]()) { result, entry in result[entry.key] = entry.value.value }
        }
        else if let v = try? container.decode([VertexAnyDecodableValue].self) {
            value = v.map(\.value)
        }
        else { value = NSNull() }
    }
}
