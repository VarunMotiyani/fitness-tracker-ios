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

    // MARK: - Fallback

    private func runWithFallback(primary: [Result<String, LLMError>],
                                fallback: [Result<String, LLMError>],
                                maxRetries: Int = 2) async -> (Result<Box, Error>, primaryCalls: Int, fallbackCalls: Int) {
        let p = StubLLMProvider(responses: primary)
        let f = StubLLMProvider(responses: fallback)
        let provider = ResilientProvider(wrapped: p, fallback: f, maxRetries: maxRetries, baseDelay: .zero)
        do {
            let r: LLMResult<Box> = try await provider.complete(system: "s", user: "u", schema: schema(), as: Box.self)
            return (.success(r.value), p.callCount, f.callCount)
        } catch {
            return (.failure(error), p.callCount, f.callCount)
        }
    }

    @Test func failsOverToFallbackAfterPrimaryExhausted() async {
        let (result, primaryCalls, fallbackCalls) = await runWithFallback(
            primary: [.failure(.rateLimited), .failure(.rateLimited), .failure(.rateLimited)],
            fallback: [.success(ok)])
        #expect(try! result.get() == Box(ok: true))
        #expect(primaryCalls == 3)   // 1 + 2 retries
        #expect(fallbackCalls == 1)  // one shot, no retry
    }

    @Test func fallbackResultIsStampedUsedFallback() async throws {
        let p = StubLLMProvider(responses: [.failure(.transport("HTTP 503"))])
        let f = StubLLMProvider(responses: [.success(ok)])
        let provider = ResilientProvider(wrapped: p, fallback: f, maxRetries: 0, baseDelay: .zero)
        let r: LLMResult<Box> = try await provider.complete(system: "s", user: "u", schema: schema(), as: Box.self)
        #expect(r.usedFallback == true)

        let noFallback = ResilientProvider(wrapped: StubLLMProvider(responses: [.success(ok)]), baseDelay: .zero)
        let r2: LLMResult<Box> = try await noFallback.complete(system: "s", user: "u", schema: schema(), as: Box.self)
        #expect(r2.usedFallback == false)
    }

    @Test func streamTextDefaultYieldsWholeCompletionOnce() async throws {
        let stub = StubLLMProvider(responses: [.success(#"{"text":"hello world"}"#)])
        var chunks: [String] = []
        for try await chunk in stub.streamText(system: "s", user: "u") { chunks.append(chunk) }
        #expect(chunks == ["hello world"])
    }

    @Test func doesNotUseFallbackWhenPrimarySucceeds() async {
        let (result, primaryCalls, fallbackCalls) = await runWithFallback(
            primary: [.success(ok)], fallback: [.success(#"{"ok":false}"#)])
        #expect(try! result.get() == Box(ok: true))
        #expect(primaryCalls == 1)
        #expect(fallbackCalls == 0)
    }

    @Test func surfacesPrimaryErrorWhenFallbackAlsoFails() async {
        let (result, _, fallbackCalls) = await runWithFallback(
            primary: [.failure(.transport("HTTP 400: primary bad"))],
            fallback: [.failure(.transport("HTTP 500: fallback bad"))])
        #expect(fallbackCalls == 1)
        if case .failure(let e) = result {
            #expect(e as? LLMError == .transport("HTTP 400: primary bad"))
        } else { Issue.record("expected failure") }
    }

    @Test func nonRetryablePrimaryErrorStillReachesFallback() async {
        let (result, primaryCalls, fallbackCalls) = await runWithFallback(
            primary: [.failure(.decoding("bad json"))], fallback: [.success(ok)])
        #expect(try! result.get() == Box(ok: true))
        #expect(primaryCalls == 1)   // decode error not retried
        #expect(fallbackCalls == 1)
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
