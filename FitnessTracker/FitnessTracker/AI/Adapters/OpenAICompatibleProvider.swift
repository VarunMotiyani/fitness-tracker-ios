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

    var capabilities: ProviderCapabilities {
        let defaults = ProviderCapabilities.openAICompatibleDefault(host: baseURL.host)
        // Groq's GPT-OSS models are trained for Harmony/native function calls.
        // The provider-neutral prompt envelope is not reliable for these
        // models (they can return a valid but differently-shaped JSON object),
        // so prefer the API's native tool lane. A stored profile override can
        // still opt back into the prompt lane when needed.
        return requiresGPTOSSNativeTools
            ? defaults.overriding(toolCalling: .native)
            : defaults
    }

    /// POSTs `body` to `chat/completions`, applying auth + extra headers, and
    /// returns the response data or throws `LLMError.transport` on a non-2xx /
    /// network failure (error bodies redacted).
    private func send(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("no HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            let snippet = Self.redactSecrets(String(decoding: data.prefix(300), as: UTF8.self))
            throw LLMError.transport("HTTP \(http.statusCode): \(snippet)")
        }
        return data
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
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
        var body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": user],
            ],
            "response_format": responseFormat,
        ]
        if requiresGPTOSSReasoningExclusion {
            // GPT-OSS does not support Groq's reasoning_format parameter. Its
            // reasoning is included in a separate field by default; disable
            // that field so JSON mode remains a clean decodable response.
            body["include_reasoning"] = false
        }
        let data = try await send(body: body)

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

    func completeToolTurn<Final: Decodable & Sendable>(
        system: String,
        messages: [ToolChatMessage],
        tools: [ToolDescriptor],
        finalSchema: JSONSchema,
        as type: Final.Type
    ) async throws -> NativeToolTurnResult<Final> {
        var wireMessages: [[String: Any]] = [[
            "role": "system",
            "content": system + "\n\nWhen you are finished calling tools, reply with a JSON object matching: " + finalSchema.json,
        ]]
        for message in messages {
            switch message.role {
            case .system, .user:
                wireMessages.append(["role": message.role.rawValue, "content": message.content ?? ""])
            case .assistant:
                var wire: [String: Any] = ["role": "assistant"]
                wire["content"] = message.content ?? ""
                if let calls = message.toolCalls {
                    wire["tool_calls"] = calls.map { call in
                        ["id": call.id, "type": "function",
                         "function": ["name": call.name, "arguments": call.argumentsJSON]]
                    }
                }
                wireMessages.append(wire)
            case .tool:
                wireMessages.append(["role": "tool",
                                     "tool_call_id": message.toolCallID ?? "",
                                     "content": message.content ?? ""])
            }
        }

        // Permissive `parameters` — the app validates tool args itself when it
        // decodes `argumentsJSON`; the shape is carried in the description so the
        // model still knows what to send.
        let wireTools: [[String: Any]] = tools.map { tool in
            ["type": "function",
             "function": [
                "name": tool.name,
                "description": tool.description + "\n\nArguments (JSON): " + tool.argsSchemaJSON,
                "parameters": ["type": "object", "additionalProperties": true],
             ]]
        }

        var body: [String: Any] = [
            "model": modelID,
            "messages": wireMessages,
            "response_format": ["type": "json_object"],
        ]
        if !wireTools.isEmpty {
            body["tools"] = wireTools
            body["tool_choice"] = "auto"
        }
        if requiresGPTOSSReasoningExclusion {
            // Keep native tool responses free of the separate reasoning field
            // as well; the model's tool arguments/content remain unchanged.
            body["include_reasoning"] = false
        }

        let data = try await send(body: body)

        let envelope: ToolEnvelope
        do { envelope = try JSONDecoder().decode(ToolEnvelope.self, from: data) }
        catch { throw LLMError.decoding("tool envelope: \(error)") }
        guard let message = envelope.choices.first?.message else { throw LLMError.emptyResponse }

        let turn: NativeToolTurn<Final>
        if let toolCalls = message.tool_calls, !toolCalls.isEmpty {
            turn = .toolCalls(toolCalls.map {
                NativeToolCall(id: $0.id, name: $0.function.name, argumentsJSON: $0.function.arguments)
            })
        } else if let content = message.content, !content.isEmpty {
            let value: Final
            do { value = try JSONDecoder().decode(Final.self, from: Data(content.utf8)) }
            catch { throw LLMError.decoding("final content: \(error)") }
            turn = .final(value)
        } else {
            throw LLMError.emptyResponse
        }

        return NativeToolTurnResult(
            turn: turn,
            inputTokens: envelope.usage?.prompt_tokens ?? 0,
            outputTokens: envelope.usage?.completion_tokens ?? 0,
            cachedTokens: envelope.usage?.prompt_tokens_details?.cached_tokens ?? 0)
    }

    /// Strips anything shaped like an OpenAI (`sk-…`) or Google (`AIza…`) key from
    /// a provider error body before it goes into an `LLMError` string.
    static func redactSecrets(_ text: String) -> String {
        text.replacing(/sk-[A-Za-z0-9_-]{8,}/, with: "«redacted»")
            .replacing(/AIza[A-Za-z0-9_-]{8,}/, with: "«redacted»")
    }

    /// Groq GPT-OSS returns reasoning in a separate field by default. Keep
    /// this vendor/model-specific so other OpenAI-compatible servers never
    /// receive Groq-only request fields.
    private var requiresGPTOSSReasoningExclusion: Bool {
        guard baseURL.host?.caseInsensitiveCompare("api.groq.com") == .orderedSame else { return false }
        let id = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return id == "openai/gpt-oss-20b" || id == "openai/gpt-oss-120b"
    }

    private var requiresGPTOSSNativeTools: Bool {
        requiresGPTOSSReasoningExclusion
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

    private struct ToolEnvelope: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                struct ToolCall: Decodable {
                    struct Function: Decodable { let name: String; let arguments: String }
                    let id: String
                    let function: Function
                }
                let content: String?
                let tool_calls: [ToolCall]?
            }
            let message: Message
        }
        let choices: [Choice]
        let usage: Envelope.Usage?
    }
}
