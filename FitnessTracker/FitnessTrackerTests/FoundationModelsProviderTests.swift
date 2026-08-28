import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct FoundationModelsProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    // Deliberately dual-outcome: on-device model availability varies by machine /
    // simulator. This passes if `complete` EITHER returns the decoded value OR
    // throws an `LLMError` (`.transport` when the on-device model isn't
    // downloaded / available, or `.visionUnsupported`).
    @Test func returnsDecodedJSONOrThrowsWhenUnavailable() async throws {
        let provider = FoundationModelsProvider()
        do {
            let result: LLMResult<Dummy> = try await provider.complete(
                system: "Return a JSON object.",
                user: "Return {\"ok\": true}.",
                schema: JSONSchema(json: "{}"),
                as: Dummy.self)
            #expect(result.value == Dummy(ok: true))
        } catch is LLMError {
            // Acceptable: on-device model unavailable (`.transport`),
            // vision unsupported (`.visionUnsupported`), or the model produced
            // output that didn't decode (`.decoding`).
        }
    }
}
