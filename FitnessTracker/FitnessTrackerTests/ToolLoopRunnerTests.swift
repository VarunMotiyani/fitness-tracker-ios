import Testing
import Foundation
@testable import FitnessTracker
import LLMKit

private struct DummyFinal: Codable, Sendable, Equatable { let value: Int }

@MainActor
@Suite struct ToolLoopRunnerTests {
    @Test func executesOneToolCallThenReturnsFinal() async throws {
        let toolTurn = """
        {"decision":"tool_call","toolCall":{"name":"convert_test","argsJSON":"{}"}}
        """
        let finalTurn = """
        {"decision":"final","final":{"value":42}}
        """
        let provider = StubLLMProvider(responses: [.success(toolTurn), .success(finalTurn)])
        let registry = ToolRegistry(tools: [EchoTool()])
        let runner = ToolLoopRunner()

        let result: ToolLoopResult<DummyFinal> = try await runner.run(
            system: "test", initialUser: "test",
            finalSchema: JSONSchema(json: "{\"value\":\"number\"}"),
            tools: registry, provider: provider)

        #expect(result.value.value == 42)
        #expect(provider.callCount == 2)
        #expect(result.calls.count == 2)
        #expect(result.calls.allSatisfy { $0.inputTokens == 10 && $0.outputTokens == 20 && $0.succeeded })
    }

    @Test func feedsToolResultBackIntoTheNextPrompt() async throws {
        let toolTurn = """
        {"decision":"tool_call","toolCall":{"name":"convert_test","argsJSON":"{}"}}
        """
        let finalTurn = """
        {"decision":"final","final":{"value":1}}
        """
        let provider = StubLLMProvider(responses: [.success(toolTurn), .success(finalTurn)])
        let registry = ToolRegistry(tools: [EchoTool()])
        let runner = ToolLoopRunner()

        let _: ToolLoopResult<DummyFinal> = try await runner.run(
            system: "test", initialUser: "start",
            finalSchema: JSONSchema(json: "{\"value\":\"number\"}"),
            tools: registry, provider: provider)

        #expect(provider.lastUser.contains("echo-result"))
    }

    @Test func exceedsMaxIterationsThrows() async throws {
        let toolTurn = """
        {"decision":"tool_call","toolCall":{"name":"convert_test","argsJSON":"{}"}}
        """
        let provider = StubLLMProvider(responses: Array(repeating: .success(toolTurn), count: 10))
        let registry = ToolRegistry(tools: [EchoTool()])
        let runner = ToolLoopRunner()

        do {
            let _: ToolLoopResult<DummyFinal> = try await runner.run(
                system: "test", initialUser: "test",
                finalSchema: JSONSchema(json: "{\"value\":\"number\"}"),
                tools: registry, provider: provider, maxIterations: 3)
            Issue.record("expected exceededMaxIterations to throw")
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            #expect(calls.count == 3) // billed even though the loop never converged
        }
        #expect(provider.callCount == 3)
    }

    @Test func returnsFinalImmediatelyWithNoToolCalls() async throws {
        let finalTurn = """
        {"decision":"final","final":{"value":7}}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let registry = ToolRegistry(tools: [])
        let runner = ToolLoopRunner()

        let result: ToolLoopResult<DummyFinal> = try await runner.run(
            system: "test", initialUser: "test",
            finalSchema: JSONSchema(json: "{\"value\":\"number\"}"),
            tools: registry, provider: provider)

        #expect(result.value.value == 7)
        #expect(provider.callCount == 1)
    }
}

private struct EchoTool: CoachTool {
    var descriptor: ToolDescriptor {
        ToolDescriptor(name: "convert_test", description: "test tool", argsSchemaJSON: "{}")
    }
    func run(argsJSON: String) -> String { "\"echo-result\"" }
}
