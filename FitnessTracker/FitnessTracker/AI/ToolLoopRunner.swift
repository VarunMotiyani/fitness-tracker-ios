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
        if provider.capabilities.toolCalling == .native {
            return try await runNative(system: system, initialUser: initialUser, finalSchema: finalSchema,
                                       tools: tools, provider: provider, maxIterations: maxIterations)
        }
        return try await runPrompt(system: system, initialUser: initialUser, finalSchema: finalSchema,
                                   tools: tools, provider: provider, maxIterations: maxIterations)
    }

    // MARK: - Prompt lane (any provider): the model emits a JSON envelope.

    private func runPrompt<Final: Codable & Sendable>(
        system: String, initialUser: String, finalSchema: JSONSchema,
        tools: ToolRegistry, provider: any LLMProvider, maxIterations: Int
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
                throw Self.classify(error, calls: &calls)
            }
            calls.append(CallOutcome(inputTokens: result.inputTokens, outputTokens: result.outputTokens,
                                     cachedTokens: result.cachedTokens, succeeded: true,
                                     usedFallback: result.usedFallback))

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

    // MARK: - Native lane: the provider's real function-calling API.

    private func runNative<Final: Codable & Sendable>(
        system: String, initialUser: String, finalSchema: JSONSchema,
        tools: ToolRegistry, provider: any LLMProvider, maxIterations: Int
    ) async throws -> ToolLoopResult<Final> {
        var messages: [ToolChatMessage] = [ToolChatMessage(role: .user, content: initialUser)]
        let descriptors = tools.descriptors()
        var calls: [CallOutcome] = []

        for _ in 0..<maxIterations {
            let result: NativeToolTurnResult<Final>
            do {
                result = try await provider.completeToolTurn(
                    system: system, messages: messages, tools: descriptors,
                    finalSchema: finalSchema, as: Final.self)
            } catch {
                throw Self.classify(error, calls: &calls)
            }
            calls.append(CallOutcome(inputTokens: result.inputTokens, outputTokens: result.outputTokens,
                                     cachedTokens: result.cachedTokens, succeeded: true,
                                     usedFallback: result.usedFallback))

            switch result.turn {
            case .final(let value):
                return ToolLoopResult(value: value, calls: calls)
            case .toolCalls(let toolCalls):
                messages.append(ToolChatMessage(role: .assistant, toolCalls: toolCalls))
                for call in toolCalls {
                    let output = tools.execute(ToolCallRequest(name: call.name, argsJSON: call.argumentsJSON))
                    messages.append(ToolChatMessage(role: .tool, content: output, toolCallID: call.id))
                }
            }
        }
        throw ToolLoopError.exceededMaxIterations(calls: calls)
    }

    /// Records the failed attempt in `calls` and maps the provider error to the
    /// right `ToolLoopError` — preserving a transport diagnostic for the
    /// interactive coach screen.
    private static func classify(_ error: Error, calls: inout [CallOutcome]) -> ToolLoopError {
        calls.append(CallOutcome(inputTokens: 0, outputTokens: 0, cachedTokens: 0, succeeded: false))
        if case LLMError.transport(let message) = error {
            return .providerFailedWithMessage(calls: calls, message: message)
        }
        return .providerFailed(calls: calls)
    }
}
