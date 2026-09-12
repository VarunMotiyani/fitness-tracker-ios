import Foundation
import LLMKit
import os

/// A model that wraps its answer in the prompt-lane envelope emits
/// `{"final": <obj>}` (or `{"decision":"final","final": <obj>}`); this pulls the
/// inner object out. File-scope because a generic type cannot nest in a generic
/// function.
private nonisolated struct PromptEnvelopeWrapper<T: Decodable>: Decodable { let final: T }

nonisolated struct OpenAICompatibleProvider: LLMProvider {
    /// Provider round-trips are otherwise invisible until they surface as a red
    /// banner. Log the outgoing shape and the *full* error body (the
    /// `LLMError.transport` string is truncated for the UI) so provider-specific
    /// 400s are diagnosable from Console without a debugger.
    private static let log = Logger(subsystem: "com.varunmotiyani.TrainSage", category: "LLMProvider")

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
        Self.log.debug("POST chat/completions host=\(baseURL.host ?? "?", privacy: .public) model=\(modelID, privacy: .public) fields=\(body.keys.sorted().joined(separator: ","), privacy: .public)")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.log.error("transport failure host=\(baseURL.host ?? "?", privacy: .public) model=\(modelID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw LLMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("no HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            let full = Self.redactSecrets(String(decoding: data, as: UTF8.self))
            Self.log.error("HTTP \(http.statusCode) host=\(baseURL.host ?? "?", privacy: .public) model=\(modelID, privacy: .public) body=\(full, privacy: .public)")
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
        var wireTools: [[String: Any]] = tools.map { tool in
            ["type": "function",
             "function": [
                "name": tool.name,
                "description": tool.description + "\n\nArguments (JSON): " + tool.argsSchemaJSON,
                "parameters": ["type": "object", "additionalProperties": true],
             ]]
        }

        // Groq's GPT-OSS models deliver their final answer as a synthetic
        // function call (Harmony "json" channel) instead of as message content,
        // and Groq rejects any tool call whose name is not in `request.tools`
        // ("attempted to call tool 'json'/'JSON' which was not in
        // request.tools"). The exact name the model picks varies by casing, so
        // register every observed variant; the parser maps any call that isn't
        // one of the real tools back to `.final`.
        let realToolNames = Set(tools.map(\.name))
        let usesJSONFinalTool = requiresGPTOSSNativeTools && !wireTools.isEmpty
        if usesJSONFinalTool {
            for name in ["json", "JSON"] {
                wireTools.append([
                    "type": "function",
                    "function": [
                        "name": name,
                        "description": "When you are done using other tools, call `json` with your final answer as a JSON object matching: " + finalSchema.json,
                        "parameters": ["type": "object", "additionalProperties": true],
                    ],
                ])
            }
        }

        var body: [String: Any] = [
            "model": modelID,
            "messages": wireMessages,
        ]
        if wireTools.isEmpty {
            // No tools this turn: the model must return the final JSON object,
            // so ask the provider to guarantee valid JSON.
            body["response_format"] = ["type": "json_object"]
        } else {
            // Many OpenAI-compatible providers 400 on `response_format:
            // json_object` sent alongside `tools` ("json mode cannot be
            // combined with tool/function calling"). The system prompt already
            // carries the final schema; on the turn the model stops calling
            // tools we rely on that plus the local decode.
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
            // A call to anything that isn't one of the real tools is GPT-OSS's
            // synthetic final-answer channel (`json`/`JSON`/…) — decode its
            // arguments as the final answer rather than trying to execute it.
            if usesJSONFinalTool, let finalCall = toolCalls.first(where: { !realToolNames.contains($0.function.name) }) {
                do { turn = .final(try Self.decodeFinal(Final.self, from: finalCall.function.arguments)) }
                catch { throw LLMError.decoding("final tool-call '\(finalCall.function.name)': \(error)") }
            } else {
                turn = .toolCalls(toolCalls.map {
                    NativeToolCall(id: $0.id, name: $0.function.name, argumentsJSON: $0.function.arguments)
                })
            }
        } else if let content = message.content, !content.isEmpty {
            do { turn = .final(try Self.decodeFinal(Final.self, from: content)) }
            catch { throw LLMError.decoding("final content: \(error)") }
        } else {
            throw LLMError.emptyResponse
        }

        return NativeToolTurnResult(
            turn: turn,
            inputTokens: envelope.usage?.prompt_tokens ?? 0,
            outputTokens: envelope.usage?.completion_tokens ?? 0,
            cachedTokens: envelope.usage?.prompt_tokens_details?.cached_tokens ?? 0)
    }

    /// Decodes the model's final answer, tolerating a model that wraps it in the
    /// prompt-lane envelope (`{"final": <obj>}` or `{"decision":"final","final":
    /// <obj>}`) — the shared Ask Coach system prompt teaches that shape for the
    /// prompt lane, so a native-lane model on the same prompt sometimes emits it
    /// — and a model that wraps its JSON in a markdown code fence. The native
    /// tool lane can't combine `tools` with schema-enforced JSON output on
    /// several providers (Gemini included), so the final answer only has a
    /// plain-text instruction behind it, and a chat-tuned model left to its own
    /// formatting defaults to fencing JSON in ```/```json exactly like it would
    /// in a normal chat reply.
    static func decodeFinal<F: Decodable>(_ type: F.Type, from json: String) throws -> F {
        let data = Data(stripMarkdownFence(json).utf8)
        if let value = try? JSONDecoder().decode(F.self, from: data) { return value }
        if let wrapped = try? JSONDecoder().decode(PromptEnvelopeWrapper<F>.self, from: data) { return wrapped.final }
        return try JSONDecoder().decode(F.self, from: data)
    }

    /// Strips a leading/trailing ``` or ```json (or any single-word language
    /// tag) code fence, if the whole string is wrapped in one. Leaves
    /// unfenced text untouched.
    static func stripMarkdownFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.count > 6 else { return text }
        trimmed.removeFirst(3)
        trimmed.removeLast(3)
        if let firstLineEnd = trimmed.firstIndex(of: "\n") {
            let firstLine = trimmed[trimmed.startIndex..<firstLineEnd]
            if !firstLine.isEmpty, !firstLine.contains(where: { $0 == "{" || $0 == "[" }) {
                trimmed.removeSubrange(trimmed.startIndex..<trimmed.index(after: firstLineEnd))
            }
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips anything shaped like an OpenAI (`sk-…`) or Google (`AIza…`) key from
    /// a provider error body before it goes into an `LLMError` string.
    static func redactSecrets(_ text: String) -> String {
        text.replacing(/sk-[A-Za-z0-9_-]{8,}/, with: "«redacted»")
            .replacing(/AIza[A-Za-z0-9_-]{8,}/, with: "«redacted»")
    }

    /// gpt-oss (OpenAI's open-weight Harmony-format model) needs the native
    /// tool lane and the synthetic-final-tool-call handling below regardless
    /// of which OpenAI-compatible host actually serves it — Groq, OpenRouter,
    /// Together, Fireworks, and a self-hosted vLLM all run the identical
    /// weights with the identical Harmony quirks. This used to be gated to
    /// `api.groq.com` as well as the model ID, which meant the exact same
    /// model running through any other host (OpenRouter included) silently
    /// lost this handling — a real gap, not a hardening nicety, since the
    /// quirk is a property of the model, not of who's hosting it.
    private var isGPTOSSModel: Bool {
        let id = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return id.hasSuffix("gpt-oss-20b") || id.hasSuffix("gpt-oss-120b")
    }

    private var requiresGPTOSSNativeTools: Bool { isGPTOSSModel }

    /// `include_reasoning` is Groq's own API extension, not part of the
    /// OpenAI-compatible spec — only Groq's endpoint understands it, so this
    /// (unlike the native-tool-lane detection above) stays host-gated.
    private var requiresGPTOSSReasoningExclusion: Bool {
        guard baseURL.host?.caseInsensitiveCompare("api.groq.com") == .orderedSame else { return false }
        return isGPTOSSModel
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
