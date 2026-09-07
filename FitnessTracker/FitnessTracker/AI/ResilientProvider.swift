import Foundation
import LLMKit

/// Wraps a provider with bounded retry on transient failures (`rateLimited`,
/// 5xx / network / timeout `transport` errors) and, optionally, one-shot
/// failover to a second provider once the primary is exhausted. Client errors
/// (`HTTP 4xx`), decode failures, and `visionUnsupported` are deterministic and
/// never retried. Cancellation propagates immediately.
///
/// Billing caveat: retries and the failover attempt are invisible to the
/// caller's per-call `AICallRecord` — a retried-away 5xx costs no tokens, and a
/// successful failover records only the fallback's call, not the primary's
/// failure. Accurate per-attempt accounting is a later follow-up.
nonisolated struct ResilientProvider: LLMProvider {
    let wrapped: any LLMProvider
    let fallback: (any LLMProvider)?
    let maxRetries: Int
    let baseDelay: Duration

    init(wrapped: any LLMProvider, fallback: (any LLMProvider)? = nil,
         maxRetries: Int = 2, baseDelay: Duration = .milliseconds(500)) {
        self.wrapped = wrapped
        self.fallback = fallback
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }

    var capabilities: ProviderCapabilities { wrapped.capabilities }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        try await attempt(
            primary: { try await wrapped.complete(system: system, user: user, schema: schema, as: type) },
            fallback: fallback.map { fb in { try await fb.complete(system: system, user: user, schema: schema, as: type) } })
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        try await attempt(
            primary: { try await wrapped.completeWithImage(system: system, user: user, image: image, schema: schema, as: type) },
            fallback: fallback.map { fb in { try await fb.completeWithImage(system: system, user: user, image: image, schema: schema, as: type) } })
    }

    /// Retry the primary; on giving up, try the fallback once. If the fallback
    /// also fails, surface the *primary's* error — the user configured the
    /// primary and that's the failure worth reporting.
    private func attempt<T: Sendable>(primary: @Sendable () async throws -> T,
                                      fallback fb: (@Sendable () async throws -> T)?) async throws -> T {
        do {
            return try await withRetry(primary)
        } catch is CancellationError {
            throw CancellationError()
        } catch let primaryError {
            guard let fb else { throw primaryError }
            do { return try await fb() }
            catch is CancellationError { throw CancellationError() }
            catch { throw primaryError }
        }
    }

    private func withRetry<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await op()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < maxRetries, Self.isRetryable(error) else { throw error }
                attempt += 1
                try await Task.sleep(for: baseDelay * (1 << (attempt - 1)))  // 0.5s, 1s, …
            }
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case LLMError.rateLimited:
            return true
        case LLMError.transport(let message):
            // "HTTP 4xx" is a client error — same request, same failure. Retry
            // everything else (5xx, connection reset, timeout, "no HTTP response").
            return !message.contains("HTTP 4")
        default:
            return false
        }
    }
}
