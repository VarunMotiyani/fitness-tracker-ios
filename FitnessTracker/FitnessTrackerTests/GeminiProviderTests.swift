import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct GeminiProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    private static func okResponse(_ req: URLRequest) -> (HTTPURLResponse, Data) {
        let body = """
        {"candidates":[{"content":{"parts":[{"text":"{\\"ok\\":true}"}]}}],
         "usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":9,"cachedContentTokenCount":2}}
        """
        return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8))
    }

    @Test func parsesTextAndUsageMetadata() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            return Self.okResponse(req)
        }

        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: session)
        let r: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                                                       schema: JSONSchema(json: "{}"), as: Dummy.self)
        #expect(r.value == Dummy(ok: true))
        #expect(r.inputTokens == 7)
        #expect(r.outputTokens == 9)
        #expect(r.cachedTokens == 2)

        let req = captured.get()
        #expect(req?.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
        #expect(req?.url?.absoluteString.contains("models/gemini-x:generateContent") == true)
    }

    @Test func responseSchemaIsSanitizedForGemini() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            return Self.okResponse(req)
        }

        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: session)
        let _: LLMResult<Dummy> = try await p.complete(
            system: "s", user: "u",
            schema: WeeklyPlanDTO.planJSONSchema, as: Dummy.self)

        let bodyData = try #require(captured.get()?.capturedBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        let generationConfig = try #require(json?["generationConfig"] as? [String: Any])
        let responseSchema = try #require(generationConfig["responseSchema"])
        #expect(!Self.containsKey("additionalProperties", in: responseSchema))
        // sanity: the schema still carries real content
        #expect(Self.containsKey("properties", in: responseSchema))
    }

    private static func containsKey(_ key: String, in obj: Any) -> Bool {
        if let dict = obj as? [String: Any] {
            if dict.keys.contains(key) { return true }
            return dict.values.contains { containsKey(key, in: $0) }
        }
        if let array = obj as? [Any] {
            return array.contains { containsKey(key, in: $0) }
        }
        return false
    }

    // MARK: - completeWithImage

    @Test func completeWithImageSendsInlineDataAndParsesResult() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            return Self.okResponse(req)
        }

        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: session)
        let imageData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let r: LLMResult<Dummy> = try await p.completeWithImage(
            system: "s", user: "u",
            image: ImagePayload(data: imageData, mimeType: "image/png"),
            schema: JSONSchema(json: "{}"), as: Dummy.self)

        #expect(r.value == Dummy(ok: true))
        #expect(r.inputTokens == 7)
        #expect(r.outputTokens == 9)
        #expect(r.cachedTokens == 2)

        let bodyData = try #require(captured.get()?.capturedBody)
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let contents = try #require(json["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        #expect(parts.contains { ($0["text"] as? String) == "u" })
        let inlinePart = try #require(parts.compactMap { $0["inlineData"] as? [String: Any] }.first)
        #expect(inlinePart["mimeType"] as? String == "image/png")
        #expect(inlinePart["data"] as? String == imageData.base64EncodedString())
    }

    // MARK: - completeToolTurn

    @Test func toolTurnParsesFunctionCall() async throws {
        let session = StubURLProtocol.session { req in
            let body = #"""
            {"candidates":[{"content":{"parts":[{"functionCall":{"name":"get_recovery","args":{"x":1,"label":"a"}}}]}}]}
            """#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: session)

        let r: NativeToolTurnResult<Dummy> = try await p.completeToolTurn(
            system: "s",
            messages: [ToolChatMessage(role: .user, content: "hi")],
            tools: [ToolDescriptor(name: "get_recovery", description: "d", argsSchemaJSON: "{}")],
            finalSchema: JSONSchema(json: #"{"ok":"bool"}"#), as: Dummy.self)

        guard case .toolCalls(let calls) = r.turn else { Issue.record("expected toolCalls"); return }
        #expect(calls.count == 1)
        #expect(calls.first?.name == "get_recovery")

        // Round-trip the args JSON instead of comparing strings — key order
        // isn't guaranteed by JSONSerialization.
        let argsJSON = try #require(calls.first?.argumentsJSON)
        let decoded = try #require(JSONSerialization.jsonObject(with: Data(argsJSON.utf8)) as? [String: Any])
        #expect(decoded["x"] as? Double == 1)
        #expect(decoded["label"] as? String == "a")
    }

    @Test func toolTurnParsesFinalAnswer() async throws {
        let session = StubURLProtocol.session { req in
            let body = """
            {"candidates":[{"content":{"parts":[{"text":"{\\"ok\\":true}"}]}}],
             "usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":7}}
            """
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: session)

        let r: NativeToolTurnResult<Dummy> = try await p.completeToolTurn(
            system: "s", messages: [ToolChatMessage(role: .user, content: "hi")],
            tools: [], finalSchema: JSONSchema(json: #"{"ok":"bool"}"#), as: Dummy.self)

        guard case .final(let value) = r.turn else { Issue.record("expected final"); return }
        #expect(value == Dummy(ok: true))
        #expect(r.inputTokens == 5)
        #expect(r.outputTokens == 7)
    }

    @Test func toolTurnSendsSanitizedFunctionDeclarationsAndFunctionResponse() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            return Self.okResponse(req)
        }
        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: session)

        let _: NativeToolTurnResult<Dummy> = try await p.completeToolTurn(
            system: "s",
            messages: [
                ToolChatMessage(role: .user, content: "hi"),
                ToolChatMessage(role: .tool, content: #"{"result":"ok"}"#, toolCallID: "get_recovery"),
            ],
            tools: [ToolDescriptor(name: "get_recovery", description: "fetches recovery",
                                    argsSchemaJSON: WeeklyPlanDTO.planJSONSchema.json)],
            finalSchema: JSONSchema(json: #"{"ok":"bool"}"#), as: Dummy.self)

        let bodyData = try #require(captured.get()?.capturedBody)
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        let toolsArray = try #require(json["tools"] as? [[String: Any]])
        let declarations = try #require(toolsArray.first?["functionDeclarations"] as? [[String: Any]])
        let declaration = try #require(declarations.first)
        #expect(declaration["name"] as? String == "get_recovery")
        #expect(declaration["description"] as? String == "fetches recovery")
        let parameters = try #require(declaration["parameters"])
        #expect(!Self.containsKey("additionalProperties", in: parameters))

        let contents = try #require(json["contents"] as? [[String: Any]])
        let hasFunctionResponse = contents.contains { content in
            let parts = content["parts"] as? [[String: Any]] ?? []
            return parts.contains { $0["functionResponse"] != nil }
        }
        #expect(hasFunctionResponse)
    }

    // MARK: - capabilities

    @Test func advertisesNativeToolCalling() {
        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: .shared)
        #expect(p.capabilities.toolCalling == .native)
    }
}
