import Foundation
import LLMKit

enum ToolLoopError: Error, Sendable, Equatable {
    /// Carries the calls made before the cap was hit so the caller can still
    /// bill them — a run that never converges still cost real tokens.
    case exceededMaxIterations(calls: [CallOutcome])
    /// A `provider.complete` call threw mid-loop. Carries every `CallOutcome`
    /// accumulated so far — the earlier successful, billed sub-calls plus a
    /// final failed one — so the caller still bills what actually happened
    /// instead of discarding it with a bare `catch`.
    case providerFailed(calls: [CallOutcome])
    /// Same as `providerFailed`, but preserves a safe provider diagnostic for
    /// the interactive coach screen (for example, Groq's HTTP 400 body).
    case providerFailedWithMessage(calls: [CallOutcome], message: String)
}

/// `ToolLoopRunner.run`'s result: the model's final answer plus one
/// `CallOutcome` per underlying `LLMProvider.complete` call made to reach it,
/// for call-granular `AICallRecord` billing (mirrors `CoordinatorResult.calls`
/// in `PlanCoordinator`).
struct ToolLoopResult<Final: Codable & Sendable>: Sendable {
    let value: Final
    let calls: [CallOutcome]
}

/// Runs the provider-agnostic tool loop (design spec §8) over
/// `LLMProvider.complete`: each turn either asks to run a tool (executed
/// deterministically, result appended to the next prompt) or returns the
/// final answer. One well-orchestrated call per touchpoint, the model's own
/// reasoning sequences the tool calls — not a manually pre-decomposed
/// pipeline, since DeepSeek/GLM/Kimi-tier models are specifically good at
/// exactly this kind of multi-step tool use.
@MainActor
struct ToolLoopRunner {
    func run<Final: Codable & Sendable>(
        system: String,
        initialUser: String,
        finalSchema: JSONSchema,
        tools: ToolRegistry,
        provider: any LLMProvider,
        maxIterations: Int = 4
    ) async throws -> ToolLoopResult<Final> {
        let schema = ToolLoopTurn<Final>.schema(finalSchema: finalSchema, tools: tools.descriptors())
        var user = initialUser
        var calls: [CallOutcome] = []

        for _ in 0..<maxIterations {
            let result: LLMResult<ToolLoopTurn<Final>>
            do {
                result = try await provider.complete(
                    system: system, user: user, schema: schema, as: ToolLoopTurn<Final>.self)
            } catch {
                calls.append(CallOutcome(inputTokens: 0, outputTokens: 0, cachedTokens: 0, succeeded: false))
                if case LLMError.transport(let message) = error {
                    throw ToolLoopError.providerFailedWithMessage(calls: calls, message: message)
                }
                throw ToolLoopError.providerFailed(calls: calls)
            }
            calls.append(CallOutcome(inputTokens: result.inputTokens, outputTokens: result.outputTokens,
                                     cachedTokens: result.cachedTokens, succeeded: true))

            switch result.value {
            case .final(let value):
                return ToolLoopResult(value: value, calls: calls)
            case .toolCall(let request):
                let toolResult = tools.execute(request)
                user += "\n\nTool '\(request.name)' returned: \(toolResult)\n\nContinue: call another tool, or give your final answer."
            }
        }
        throw ToolLoopError.exceededMaxIterations(calls: calls)
    }
}
