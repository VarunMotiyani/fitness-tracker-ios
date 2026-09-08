import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct OpenAICompatibleProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    @Test func parsesContentAndUsage() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            let body = """
            {"choices":[{"message":{"content":"{\\"ok\\":true}"}}],
             "usage":{"prompt_tokens":11,"completion_tokens":22,"prompt_tokens_details":{"cached_tokens":3}}}
            """
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }

        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://api.example.com/v1")!,
                                         apiKey: "sk-test", modelID: "gpt-x",
                                         session: session)
        let r: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                                                       schema: JSONSchema(json: "{}"), as: Dummy.self)
        #expect(r.value == Dummy(ok: true))
        #expect(r.inputTokens == 11)
        #expect(r.outputTokens == 22)
        #expect(r.cachedTokens == 3)

        // Request assertions run here, on the test task, after the await returned.
        let req = captured.get()
        #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(req?.url?.path.hasSuffix("/chat/completions") == true)
        #expect(req?.httpMethod == "POST")
    }

    @Test func usesJSONModeForPromptSchemas() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            let body = #"{"choices":[{"message":{"content":"{\"ok\":true}"}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }

        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                                         apiKey: "sk-test", modelID: "qwen/qwen3.8-27b",
                                         session: session)
        let _: LLMResult<Dummy> = try await p.complete(
            system: "Return only JSON.", user: "hi",
            schema: JSONSchema(json: #"{"reply":"string"}"#), as: Dummy.self)

        let requestBody = try #require(captured.get()?.capturedBody)
        let object = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        let format = try #require(object["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_object")
    }

    @Test func groqGPTOSSExcludesReasoningWithJSONMode() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            let body = #"{"choices":[{"message":{"content":"{\"ok\":true}"}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }

        let p = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.groq.com/openai/v1")!,
            apiKey: "gsk-test", modelID: "openai/gpt-oss-120b", session: session)
        let _: LLMResult<Dummy> = try await p.complete(
            system: "Return only JSON.", user: "hi",
            schema: JSONSchema(json: #"{"ok":"bool"}"#), as: Dummy.self)

        let requestBody = try #require(captured.get()?.capturedBody)
        let object = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(object["include_reasoning"] as? Bool == false)
    }

    @Test func usesJSONModeWhenPromptSchemaIsDescriptiveJSON() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            let body = #"{"choices":[{"message":{"content":"{\"ok\":true}"}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }
        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                                         apiKey: "sk-test", modelID: "qwen/qwen3.8-27b",
                                         session: session)
        let _: LLMResult<Dummy> = try await p.complete(
            system: "Return only JSON.", user: "hi",
            schema: JSONSchema(json: ##"{"decision":"tool_call | final", "_tools": {"x": {"arg":"string"} // note}}"##), as: Dummy.self)
        let requestBody = try #require(captured.get()?.capturedBody)
        let object = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        let format = try #require(object["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_object")
    }

    @Test func httpErrorBecomesTransportError() async {
        let session = StubURLProtocol.session { req in
            (HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"slow down"}"#.utf8))
        }
        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://x/v1")!, apiKey: nil,
                                         modelID: "m", session: session)
        await #expect(throws: LLMError.self) {
            let _: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                schema: JSONSchema(json: "{}"), as: Dummy.self)
        }
    }

    @Test func redactsKeyShapesFromErrorBody() {
        let redacted = OpenAICompatibleProvider.redactSecrets(
            "Incorrect API key provided: sk-ABCDEFGH12345678 and AIzaSyABCDEFGH12345678")
        #expect(!redacted.contains("sk-ABCDEFGH12345678"))
        #expect(!redacted.contains("AIzaSyABCDEFGH12345678"))
    }

    // MARK: - Native tool turn

    @Test func toolTurnSendsToolsAndParsesToolCalls() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            let body = #"{"choices":[{"message":{"content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"get_recovery","arguments":"{\"x\":1}"}}]}}]}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://api.example.com/v1")!,
                                         apiKey: "sk-test", modelID: "gpt-x", session: session)

        let r: NativeToolTurnResult<Dummy> = try await p.completeToolTurn(
            system: "s",
            messages: [ToolChatMessage(role: .user, content: "hi")],
            tools: [ToolDescriptor(name: "get_recovery", description: "d", argsSchemaJSON: "{}")],
            finalSchema: JSONSchema(json: #"{"ok":"bool"}"#), as: Dummy.self)

        guard case .toolCalls(let calls) = r.turn else { Issue.record("expected toolCalls"); return }
        #expect(calls.first?.name == "get_recovery")
        #expect(calls.first?.id == "call_1")
        #expect(calls.first?.argumentsJSON == #"{"x":1}"#)

        let bodyData = try #require(captured.get()?.capturedBody)
        let obj = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(obj["tools"] != nil)
        #expect(obj["tool_choice"] as? String == "auto")
    }

    @Test func toolTurnParsesFinalAnswer() async throws {
        let session = StubURLProtocol.session { req in
            let body = #"{"choices":[{"message":{"content":"{\"ok\":true}"}}],"usage":{"prompt_tokens":5,"completion_tokens":7}}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://api.example.com/v1")!,
                                         apiKey: nil, modelID: "gpt-x", session: session)

        let r: NativeToolTurnResult<Dummy> = try await p.completeToolTurn(
            system: "s", messages: [ToolChatMessage(role: .user, content: "hi")],
            tools: [], finalSchema: JSONSchema(json: "{}"), as: Dummy.self)

        guard case .final(let value) = r.turn else { Issue.record("expected final"); return }
        #expect(value == Dummy(ok: true))
        #expect(r.inputTokens == 5)
        #expect(r.outputTokens == 7)
    }

    @Test func officialHostAdvertisesNativeToolCalling() {
        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://api.openai.com/v1")!,
                                         apiKey: "sk", modelID: "gpt-4o", session: .shared)
        #expect(p.capabilities.toolCalling == .native)
        let groq = OpenAICompatibleProvider(baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                                            apiKey: "sk", modelID: "qwen", session: .shared)
        #expect(groq.capabilities.toolCalling == .viaPrompt)
        let groqGPTOSS = OpenAICompatibleProvider(baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                                                  apiKey: "gsk", modelID: "openai/gpt-oss-120b", session: .shared)
        #expect(groqGPTOSS.capabilities.toolCalling == .native)
    }
}
