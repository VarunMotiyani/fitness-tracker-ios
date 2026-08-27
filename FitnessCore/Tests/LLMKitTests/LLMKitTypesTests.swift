import Testing
import Foundation
@testable import LLMKit

private struct Dummy: Decodable, Sendable, Equatable { let ok: Bool }

private struct StubProvider: LLMProvider {
    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        let data = #"{"ok":true}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(Value.self, from: data)
        return LLMResult(value: value, inputTokens: 10, outputTokens: 2, cachedTokens: 0,
                         rawJSON: #"{"ok":true}"#)
    }
    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}

@Test func callTypeHasSixCases() {
    #expect(LLMCallType.allCases.count == 6)
}

@Test func stubProviderRoundTrips() async throws {
    let result: LLMResult<Dummy> = try await StubProvider()
        .complete(system: "s", user: "u", schema: JSONSchema(json: "{}"), as: Dummy.self)
    #expect(result.value == Dummy(ok: true))
    #expect(result.inputTokens == 10)
}

@Test func visionCallThrowsUnsupported() async {
    await #expect(throws: LLMError.visionUnsupported) {
        let _: LLMResult<Dummy> = try await StubProvider()
            .completeWithImage(system: "s", user: "u",
                               image: ImagePayload(data: Data(), mimeType: "image/jpeg"),
                               schema: JSONSchema(json: "{}"), as: Dummy.self)
    }
}
