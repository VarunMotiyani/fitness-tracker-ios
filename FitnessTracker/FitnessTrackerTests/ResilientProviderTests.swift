import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

private struct Box: Decodable, Sendable, Equatable { let ok: Bool }

@MainActor
struct ResilientProviderTests {
    private func schema() -> JSONSchema { JSONSchema(json: #"{"ok":"bool"}"#) }
    private let ok = #"{"ok":true}"#

    private func run(_ responses: [Result<String, LLMError>], maxRetries: Int = 2)
        async -> (Result<Box, Error>, Int)
    {
        let stub = StubLLMProvider(responses: responses)
        let provider = ResilientProvider(wrapped: stub, maxRetries: maxRetries, baseDelay: .zero)
        do {
            let r: LLMResult<Box> = try await provider.complete(system: "s", user: "u", schema: schema(), as: Box.self)
            return (.success(r.value), stub.callCount)
        } catch {
            return (.failure(error), stub.callCount)
        }
    }

    @Test func retriesRateLimitThenSucceeds() async {
        let (result, calls) = await run([.failure(.rateLimited), .failure(.rateLimited), .success(ok)])
        #expect(try! result.get() == Box(ok: true))
        #expect(calls == 3)
    }

    @Test func retriesTransient5xxThenSucceeds() async {
        let (result, calls) = await run([.failure(.transport("HTTP 503: upstream")), .success(ok)])
        #expect(try! result.get() == Box(ok: true))
        #expect(calls == 2)
    }

    @Test func doesNotRetryClientError() async {
        let (result, calls) = await run([.failure(.transport("HTTP 400: bad request")), .success(ok)])
        #expect((try? result.get()) == nil)
        #expect(calls == 1)
    }

    @Test func doesNotRetryDecodeError() async {
        let (result, calls) = await run([.failure(.decoding("content: x")), .success(ok)])
        #expect((try? result.get()) == nil)
        #expect(calls == 1)
    }

    @Test func givesUpAfterMaxRetriesAndThrowsLastError() async {
        let (result, calls) = await run([.failure(.rateLimited), .failure(.rateLimited), .failure(.rateLimited)], maxRetries: 2)
        #expect(calls == 3)
        if case .failure(let e) = result { #expect(e as? LLMError == .rateLimited) } else { Issue.record("expected failure") }
    }

    @Test func passesCapabilitiesThrough() {
        let stub = StubLLMProvider(responses: [])
        let provider = ResilientProvider(wrapped: stub)
        #expect(provider.capabilities == stub.capabilities)
    }

    @Test func isRetryableClassification() {
        #expect(ResilientProvider.isRetryable(LLMError.rateLimited))
        #expect(ResilientProvider.isRetryable(LLMError.transport("HTTP 500: x")))
        #expect(ResilientProvider.isRetryable(LLMError.transport("no HTTP response")))
        #expect(!ResilientProvider.isRetryable(LLMError.transport("HTTP 401: bad key")))
        #expect(!ResilientProvider.isRetryable(LLMError.decoding("x")))
        #expect(!ResilientProvider.isRetryable(LLMError.visionUnsupported))
    }
}
