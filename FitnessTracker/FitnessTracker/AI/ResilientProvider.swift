import Foundation
import LLMKit

/// Wraps a provider with bounded retry on transient failures (`rateLimited`,
/// 5xx / network / timeout `transport` errors) and, optionally, one-shot
/// failover to a second provider once the primary is exhausted. Client errors
/// (`HTTP 4xx`), decode failures, and `visionUnsupported` are deterministic and
/// never retried. Cancellation propagates immediately.
///
/// Billing: retried-away transient failures cost no tokens, so a single
/// `AICallRecord` for the eventual success is accurate. A successful failover
/// stamps `usedFallback` on the result (and thus on the `AICallRecord`), so
/// the ledger reflects which provider answered. The primary's failed attempt
/// isn't separately billed — `LLMError` doesn't carry usage, so its cost (if
/// any, e.g. a 200 that failed to decode) can't be recovered here.
nonisolated struct ResilientProvider: LLMProvider {
    let wrapped: any LLMProvider
    let fallback: (any LLMProvider)?
    let capabilitiesOverride: ProviderCapabilities?
    let maxRetries: Int
    let baseDelay: Duration

    init(wrapped: any LLMProvider, fallback: (any LLMProvider)? = nil,
         capabilitiesOverride: ProviderCapabilities? = nil,
         maxRetries: Int = 2, baseDelay: Duration = .milliseconds(500)) {
        self.wrapped = wrapped
        self.fallback = fallback
        self.capabilitiesOverride = capabilitiesOverride
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }

    var capabilities: ProviderCapabilities { capabilitiesOverride ?? wrapped.capabilities }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        let outcome = try await attempt(
            primary: { try await wrapped.complete(system: system, user: user, schema: schema, as: type) },
            fallback: fallback.map { fb in { try await fb.complete(system: system, user: user, schema: schema, as: type) } })
        var result = outcome.result
        if outcome.usedFallback { result.usedFallback = true }
        return result
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        let outcome = try await attempt(
            primary: { try await wrapped.completeWithImage(system: system, user: user, image: image, schema: schema, as: type) },
            fallback: fallback.map { fb in { try await fb.completeWithImage(system: system, user: user, image: image, schema: schema, as: type) } })
        var result = outcome.result
        if outcome.usedFallback { result.usedFallback = true }
        return result
    }

    /// Native tool turns fail over too. If the fallback is a prompt-lane
    /// provider its `completeToolTurn` throws `.unsupported` and the primary's
    /// error is surfaced — the coach loop then degrades to a normal provider
    /// failure. (Inlined rather than routed through `attempt` — a tuple of
    /// `NativeToolTurnResult<Final>` currently crashes the Swift type checker.)
    func completeToolTurn<Final: Decodable & Sendable>(
        system: String, messages: [ToolChatMessage], tools: [ToolDescriptor],
        finalSchema: JSONSchema, as type: Final.Type
    ) async throws -> NativeToolTurnResult<Final> {
        do {
            return try await withRetry {
                try await wrapped.completeToolTurn(system: system, messages: messages, tools: tools,
                                                   finalSchema: finalSchema, as: type)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let primaryError {
            guard let fb = fallback else { throw primaryError }
            do {
                var result = try await fb.completeToolTurn(system: system, messages: messages, tools: tools,
                                                           finalSchema: finalSchema, as: type)
                result.usedFallback = true
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw primaryError
            }
        }
    }

    /// Retry the primary; on giving up, try the fallback once. If the fallback
    /// also fails, surface the *primary's* error — the user configured the
    /// primary and that's the failure worth reporting. `usedFallback` in the
    /// return tells the caller to stamp the result.
    private func attempt<T: Sendable>(
        primary: @Sendable () async throws -> T,
        fallback fb: (@Sendable () async throws -> T)?
    ) async throws -> (result: T, usedFallback: Bool) {
        do {
            return (try await withRetry(primary), false)
        } catch is CancellationError {
            throw CancellationError()
        } catch let primaryError {
            guard let fb else { throw primaryError }
            do { return (try await fb(), true) }
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
