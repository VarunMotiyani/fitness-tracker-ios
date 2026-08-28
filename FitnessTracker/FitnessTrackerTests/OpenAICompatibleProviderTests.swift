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
}
