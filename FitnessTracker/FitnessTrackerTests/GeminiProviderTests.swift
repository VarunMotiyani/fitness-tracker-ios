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
}
