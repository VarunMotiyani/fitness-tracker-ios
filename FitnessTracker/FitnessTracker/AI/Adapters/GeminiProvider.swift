import Foundation
import LLMKit
import os

nonisolated struct GeminiProvider: LLMProvider {
    /// Was silently missing — a Gemini failure had no Console trail at all,
    /// unlike every other adapter (`OpenAICompatibleProvider` logs every
    /// request/error). Same subsystem/category shape as that adapter's log.
    private static let log = Logger(subsystem: "com.varunmotiyani.TrainSage", category: "LLMProvider")

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
        Self.log.debug("POST generateContent model=\(modelID, privacy: .public) keyLen=\(apiKey.count, privacy: .public) fields=\(body.keys.sorted().joined(separator: ","), privacy: .public)")

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch {
            Self.log.error("transport failure model=\(modelID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw LLMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("no HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            let full = OpenAICompatibleProvider.redactSecrets(String(decoding: data, as: UTF8.self))
            Self.log.error("HTTP \(http.statusCode) model=\(modelID, privacy: .public) body=\(full, privacy: .public)")
            let snippet = OpenAICompatibleProvider.redactSecrets(String(decoding: data.prefix(300), as: UTF8.self))
            throw LLMError.transport("HTTP \(http.statusCode): \(snippet)")
        }
        return data
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        // Gemini's `Schema` proto has no `additionalProperties`; sending it
        // (the shared schema sets it for OpenAI strict mode) yields a 400.
        let schemaObject = Self.normalizeSchema(
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

    /// Multimodal turn: the image goes in as an `inlineData` part alongside the
    /// text prompt, base64-encoded per Gemini's `Blob` proto. Same
    /// `responseSchema` structured-output path as `complete`.
    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        let schemaObject = Self.normalizeSchema(
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
            let schemaObject = (try? Self.normalizeSchema(
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
                "responseSchema": (try? Self.normalizeSchema(
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
                return NativeToolCall(
                    id: call.id ?? "",
                    name: call.name,
                    argumentsJSON: argsJSON,
                    thoughtSignature: signature)
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

    /// Converts both standard JSON Schema and this app's compact prompt schema
    /// (`{"reply":"string"}` / `[{"name":"string"}]`) to Gemini's Schema
    /// wire format. Response schemas use the protobuf enum spelling (OBJECT,
    /// STRING, ...); function-declaration parameters use JSON-schema spelling.
    /// Gemini rejects `additionalProperties`, so it is intentionally omitted.
    static func normalizeSchema(_ obj: Any, uppercaseTypes: Bool = true) -> Any {
        let objectType = uppercaseTypes ? "OBJECT" : "object"
        let arrayType = uppercaseTypes ? "ARRAY" : "array"
        if let dict = obj as? [String: Any] {
            if let rawType = dict["type"] as? String {
                var out: [String: Any] = [:]
                for (key, value) in dict where key != "type" && key != "additionalProperties" {
                    switch key {
                    case "properties":
                        if let properties = value as? [String: Any] {
                            out[key] = properties.mapValues { normalizeSchema($0, uppercaseTypes: uppercaseTypes) }
                        }
                    case "items":
                        out[key] = normalizeSchema(value, uppercaseTypes: uppercaseTypes)
                    case "anyOf", "oneOf":
                        if let schemas = value as? [Any] {
                            out[key] = schemas.map { normalizeSchema($0, uppercaseTypes: uppercaseTypes) }
                        }
                    default:
                        // `required`, `enum`, descriptions, limits, and nullable
                        // are already represented in the correct JSON shape.
                        out[key] = value
                    }
                }
                out["type"] = geminiType(rawType, uppercaseTypes: uppercaseTypes)
                return out
            }

            let properties = dict.filter { !$0.key.hasPrefix("_") }
                .mapValues { normalizeSchema($0, uppercaseTypes: uppercaseTypes) }
            var out: [String: Any] = ["type": objectType, "properties": properties]
            if !properties.isEmpty { out["required"] = properties.keys.sorted() }
            return out
        }
        if let array = obj as? [Any] {
            guard array.count == 1 else { return array }
            return ["type": arrayType, "items": normalizeSchema(array[0], uppercaseTypes: uppercaseTypes)]
        }
        if let compact = obj as? String {
            return compactStringSchema(compact, uppercaseTypes: uppercaseTypes)
        }
        return obj
    }

    private static func geminiType(_ raw: String, uppercaseTypes: Bool) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = lower.split { $0 == " " || $0 == "," || $0 == "?" || $0 == "—" }.first.map(String.init) ?? lower
        let canonical: String
        switch token {
        case "bool", "boolean": canonical = "boolean"
        case "int", "integer": canonical = "integer"
        case "float", "double", "number": canonical = "number"
        case "array", "list": canonical = "array"
        case "object", "dictionary", "map": canonical = "object"
        case "null": canonical = "null"
        default: canonical = "string"
        }
        return uppercaseTypes ? canonical.uppercased() : canonical
    }

    private static func compactStringSchema(_ raw: String, uppercaseTypes: Bool) -> [String: Any] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonNull = pieces.filter { $0.lowercased() != "null" }
        let nullable = pieces.count != nonNull.count || trimmed.hasSuffix("?")
        let first = nonNull.first ?? "string"
        let known = ["string", "number", "integer", "int", "float", "double", "boolean", "bool", "array", "list", "object", "dictionary", "map"]
        let token = first.lowercased().split { $0 == " " || $0 == "," || $0 == "?" || $0 == "—" }.first.map(String.init) ?? "string"
        if known.contains(token) {
            var schema: [String: Any] = ["type": geminiType(token, uppercaseTypes: uppercaseTypes)]
            if nullable { schema["nullable"] = true }
            return schema
        }
        if nonNull.count > 1 {
            return ["type": uppercaseTypes ? "STRING" : "string", "enum": nonNull]
        }
        return ["type": uppercaseTypes ? "STRING" : "string", "description": trimmed]
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
                let args: [String: AnyDecodableValue]?
            }
            let text: String?
            let functionCall: FunctionCall?
            let thoughtSignature: String?
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
