import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

@Suite(.serialized)
struct OpenAICompatibleProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    @Test func parsesContentAndUsage() async throws {
        StubURLProtocol.handler = { req in
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            let body = """
            {"choices":[{"message":{"content":"{\\"ok\\":true}"}}],
             "usage":{"prompt_tokens":11,"completion_tokens":22,"prompt_tokens_details":{"cached_tokens":3}}}
            """
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://api.example.com/v1")!,
                                         apiKey: "sk-test", modelID: "gpt-x",
                                         session: StubURLProtocol.session())
        let r: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                                                       schema: JSONSchema(json: "{}"), as: Dummy.self)
        #expect(r.value == Dummy(ok: true))
        #expect(r.inputTokens == 11)
        #expect(r.outputTokens == 22)
        #expect(r.cachedTokens == 3)
    }

    @Test func httpErrorBecomesTransportError() async {
        StubURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"slow down"}"#.utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://x/v1")!, apiKey: nil,
                                         modelID: "m", session: StubURLProtocol.session())
        await #expect(throws: LLMError.self) {
            let _: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                schema: JSONSchema(json: "{}"), as: Dummy.self)
        }
    }
}
