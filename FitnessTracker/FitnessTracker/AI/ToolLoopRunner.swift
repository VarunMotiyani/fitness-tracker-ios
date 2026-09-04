import Foundation
import LLMKit

enum ToolLoopError: Error, Sendable, Equatable {
    case exceededMaxIterations
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
    ) async throws -> Final {
        let schema = ToolLoopTurn<Final>.schema(finalSchema: finalSchema, tools: tools.descriptors())
        var user = initialUser

        for _ in 0..<maxIterations {
            let result = try await provider.complete(
                system: system, user: user, schema: schema, as: ToolLoopTurn<Final>.self)

            switch result.value {
            case .final(let value):
                return value
            case .toolCall(let request):
                let toolResult = tools.execute(request)
                user += "\n\nTool '\(request.name)' returned: \(toolResult)\n\nContinue: call another tool, or give your final answer."
            }
        }
        throw ToolLoopError.exceededMaxIterations
    }
}
