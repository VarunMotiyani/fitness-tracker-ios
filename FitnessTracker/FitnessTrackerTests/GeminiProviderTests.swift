import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

@Suite(.serialized)
struct GeminiProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    @Test func parsesTextAndUsageMetadata() async throws {
        StubURLProtocol.handler = { req in
            #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
            #expect(req.url?.absoluteString.contains("models/gemini-x:generateContent") == true)
            let body = """
            {"candidates":[{"content":{"parts":[{"text":"{\\"ok\\":true}"}]}}],
             "usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":9,"cachedContentTokenCount":2}}
            """
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: StubURLProtocol.session())
        let r: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                                                       schema: JSONSchema(json: "{}"), as: Dummy.self)
        #expect(r.value == Dummy(ok: true))
        #expect(r.inputTokens == 7)
        #expect(r.outputTokens == 9)
        #expect(r.cachedTokens == 2)
    }
}
