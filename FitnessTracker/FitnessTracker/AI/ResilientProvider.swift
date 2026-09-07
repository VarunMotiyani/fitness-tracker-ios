import Foundation
import LLMKit

/// Wraps a provider with bounded retry on transient failures (`rateLimited`,
/// 5xx / network / timeout `transport` errors). Client errors (`HTTP 4xx`),
/// decode failures, and `visionUnsupported` are deterministic and never
/// retried. Cancellation propagates immediately.
///
/// Retries are invisible to billing: a transient 5xx/429 that gets retried
/// away generally costs no tokens, so the single `AICallRecord` for the
/// eventual outcome is close enough. Fallback to a second provider is a later
/// addition — `ProviderProfile.fallbackProfileID` is the hook; this only
/// retries the one provider.
nonisolated struct ResilientProvider: LLMProvider {
    let wrapped: any LLMProvider
    let maxRetries: Int
    let baseDelay: Duration

    init(wrapped: any LLMProvider, maxRetries: Int = 2, baseDelay: Duration = .milliseconds(500)) {
        self.wrapped = wrapped
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }

    var capabilities: ProviderCapabilities { wrapped.capabilities }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        try await withRetry { try await wrapped.complete(system: system, user: user, schema: schema, as: type) }
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        try await withRetry { try await wrapped.completeWithImage(system: system, user: user, image: image, schema: schema, as: type) }
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
