import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct VertexAIProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    @Test func supportsMultimodalAndNativeTools() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            let body = #"{"candidates":[{"content":{"parts":[{"text":"{\"ok\":true}"}]}}]}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let base = URL(string: "https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google/models/")!
        let p = VertexAIProvider(bearerToken: "token", modelsBaseURL: base, modelID: "gemini-3.8-flash", session: session)

        let _: LLMResult<Dummy> = try await p.completeWithImage(
            system: "s", user: "u", image: ImagePayload(data: Data([1, 2]), mimeType: "image/png"),
            schema: JSONSchema(json: "{}"), as: Dummy.self)

        #expect(p.capabilities.toolCalling == .native)
        #expect(p.capabilities.structuredOutput == .nativeJSONSchema)
        #expect(captured.get()?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let body = try #require(captured.get()?.capturedBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let parts = try #require(((json["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]]))
        #expect(parts.contains { ($0["inlineData"] as? [String: Any])?["mimeType"] as? String == "image/png" })
        let config = try #require(json["generationConfig"] as? [String: Any])
        #expect((config["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "low")
    }

    @Test func toolTurnPreservesVertexFunctionCallMetadata() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { req in
            captured.set(req)
            let body = #"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"get_recovery","args":{"days":7},"id":"vertex-call-1"},"thoughtSignature":"vertex-sig-1"}]}}]}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let base = URL(string: "https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google/models/")!
        let p = VertexAIProvider(bearerToken: "token", modelsBaseURL: base,
                                 modelID: "gemini-3.7-flash", session: session)

        let result: NativeToolTurnResult<Dummy> = try await p.completeToolTurn(
            system: "s", messages: [ToolChatMessage(role: .user, content: "hi")],
            tools: [ToolDescriptor(name: "get_recovery", description: "d", argsSchemaJSON: "{}")],
            finalSchema: JSONSchema(json: #"{"ok":"bool"}"#), as: Dummy.self)

        guard case .toolCalls(let calls) = result.turn else {
            Issue.record("expected a Vertex function call")
            return
        }
        #expect(calls.first?.id == "vertex-call-1")
        #expect(calls.first?.thoughtSignature == "vertex-sig-1")
        let body = try #require(captured.get()?.capturedBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["toolConfig"] as? [String: Any]) != nil)
        #expect(captured.get()?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(captured.get()?.url?.absoluteString.contains("gemini-3.7-flash:generateContent") == true)
    }
}
