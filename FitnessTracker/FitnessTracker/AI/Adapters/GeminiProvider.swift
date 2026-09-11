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

    // Native function calling is implemented below (`completeToolTurn`), so
    // Gemini gets the real tool lane instead of the manual prompt loop.
    var capabilities: ProviderCapabilities { .googleResponseSchema.overriding(toolCalling: .native) }

    private func send(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "models/\(modelID):generateContent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
        // Gemini's `Schema` proto has no `additionalProperties`; sending it
        // (the shared schema sets it for OpenAI strict mode) yields a 400.
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

    /// Multimodal turn: the image goes in as an `inlineData` part alongside the
    /// text prompt, base64-encoded per Gemini's `Blob` proto. Same
    /// `responseSchema` structured-output path as `complete`.
    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        let schemaObject = Self.sanitizeSchema(
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

    /// Native function-calling turn. Gemini's wire shape: outgoing tools are
    /// `tools: [{functionDeclarations: [{name, description, parameters}]}]`;
    /// a model turn that wants to call tools comes back as one or more
    /// `functionCall` parts (Gemini supports parallel calls in one response);
    /// the reply for each goes back as a `functionResponse` part on a `role:
    /// "user"` content entry (Gemini has no separate "tool" role — the
    /// request/response cycle stays user/model, matching the Python/JS SDKs).
    /// `responseSchema` cannot be combined with `tools` in the same request
    /// (matches the OpenAI-compatible json_object/tools restriction), so the
    /// final answer is asked for in the system prompt and decoded locally.
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
                continue // folded into system_instruction below
            case .user:
                contents.append(["role": "user", "parts": [["text": message.content ?? ""]]])
            case .assistant:
                if let calls = message.toolCalls, !calls.isEmpty {
                    contents.append(["role": "model", "parts": calls.map { call -> [String: Any] in
                        let args = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) ?? [String: Any]()
                        return ["functionCall": ["name": call.name, "args": args]]
                    }])
                } else {
                    contents.append(["role": "model", "parts": [["text": message.content ?? ""]]])
                }
            case .tool:
                let responseObject = (try? JSONSerialization.jsonObject(with: Data((message.content ?? "{}").utf8)))
                    ?? ["result": message.content ?? ""]
                contents.append(["role": "user", "parts": [[
                    "functionResponse": ["name": message.toolCallID ?? "", "response": responseObject],
                ]]])
            }
        }

        let wireTools: [[String: Any]] = tools.map { tool in
            let schemaObject = (try? Self.sanitizeSchema(
                JSONSerialization.jsonObject(with: Data(tool.argsSchemaJSON.utf8)))) ?? ["type": "object"]
            return ["name": tool.name, "description": tool.description, "parameters": schemaObject]
        }

        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": system + "\n\nWhen you are finished calling tools, reply with a JSON object matching: " + finalSchema.json]]],
            "contents": contents,
        ]
        if !wireTools.isEmpty {
            body["tools"] = [["functionDeclarations": wireTools]]
        }

        let data = try await send(body: body)

        let envelope: ToolEnvelope
        do { envelope = try JSONDecoder().decode(ToolEnvelope.self, from: data) }
        catch { throw LLMError.decoding("tool envelope: \(error)") }
        guard let parts = envelope.candidates.first?.content.parts else { throw LLMError.emptyResponse }

        let functionCalls = parts.compactMap(\.functionCall)
        let turn: NativeToolTurn<Final>
        if !functionCalls.isEmpty {
            turn = .toolCalls(functionCalls.map { call in
                let args = call.args?.reduce(into: [String: Any]()) { result, entry in
                    result[entry.key] = entry.value.value
                } ?? [:]
                let argsJSON = (try? JSONSerialization.data(withJSONObject: args))
                    .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                // Gemini doesn't hand back a call id; the function name is
                // stable enough to correlate the matching functionResponse.
                return NativeToolCall(id: call.name, name: call.name, argumentsJSON: argsJSON)
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

    /// Recursively drops every `additionalProperties` key (at any depth) from a
    /// parsed JSON-schema object so it is accepted by Gemini's `responseSchema`
    /// / function-declaration `parameters`.
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

    private struct ToolEnvelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable { let parts: [Part] }
            let content: Content
        }
        struct Part: Decodable {
            struct FunctionCall: Decodable {
                let name: String
                let args: [String: AnyDecodableValue]?
            }
            let text: String?
            let functionCall: FunctionCall?
        }
        let candidates: [Candidate]
        let usageMetadata: Envelope.Usage?
    }
}

/// Decodes an arbitrary JSON value (Gemini's `functionCall.args` is a
/// dynamically-shaped object) into a plain `Any` for re-serialization.
private nonisolated struct AnyDecodableValue: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([String: AnyDecodableValue].self) {
            value = v.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = entry.value.value
            }
        }
        else if let v = try? container.decode([AnyDecodableValue].self) {
            value = v.map { $0.value }
        }
        else { value = NSNull() }
    }
}
