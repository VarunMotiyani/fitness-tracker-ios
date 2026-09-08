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

    @Test func providerFailureCarriesPriorCallsForBilling() async throws {
        let toolTurn = """
        {"decision":"tool_call","toolCall":{"name":"convert_test","argsJSON":"{}"}}
        """
        // One valid tool-call turn (billed), then the provider throws.
        let provider = StubLLMProvider(responses: [.success(toolTurn), .failure(.emptyResponse)])
        let registry = ToolRegistry(tools: [EchoTool()])
        let runner = ToolLoopRunner()

        do {
            let _: ToolLoopResult<DummyFinal> = try await runner.run(
                system: "test", initialUser: "test",
                finalSchema: JSONSchema(json: "{\"value\":\"number\"}"),
                tools: registry, provider: provider, maxIterations: 4)
            Issue.record("expected providerFailed to throw")
        } catch let ToolLoopError.providerFailed(calls) {
            #expect(calls.count == 2)
            #expect(calls[0].succeeded == true)
            #expect(calls[1].succeeded == false)
            #expect(calls[1].inputTokens == 0 && calls[1].outputTokens == 0 && calls[1].cachedTokens == 0)
        }
        #expect(provider.callCount == 2)
    }

    @Test func providerTransportFailurePreservesSafeDiagnostic() async throws {
        let provider = StubLLMProvider(responses: [.failure(.transport("HTTP 400: invalid response format"))])
        let runner = ToolLoopRunner()

        do {
            let _: ToolLoopResult<DummyFinal> = try await runner.run(
                system: "test", initialUser: "test",
                finalSchema: JSONSchema(json: "{\"value\":\"number\"}"),
                tools: ToolRegistry(tools: []), provider: provider)
            Issue.record("expected provider failure to throw")
        } catch let ToolLoopError.providerFailedWithMessage(calls, message) {
            #expect(calls.count == 1)
            #expect(message == "HTTP 400: invalid response format")
        }
    }

    @Test func providerDecodingFailurePreservesSafeDiagnostic() async throws {
        let provider = StubLLMProvider(responses: [.failure(.decoding("content: keyNotFound"))])
        let runner = ToolLoopRunner()

        do {
            let _: ToolLoopResult<DummyFinal> = try await runner.run(
                system: "test", initialUser: "test",
                finalSchema: JSONSchema(json: "{\"value\":\"number\"}"),
                tools: ToolRegistry(tools: []), provider: provider)
            Issue.record("expected provider failure to throw")
        } catch let ToolLoopError.providerFailedWithMessage(calls, message) {
            #expect(calls.count == 1)
            #expect(message == "content: keyNotFound")
        }
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

    // MARK: - Native lane

    @Test func nativeLaneRunsOneToolCallThenReturnsFinal() async throws {
        let stub = NativeToolStub()
        let runner = ToolLoopRunner()

        let result: ToolLoopResult<DummyFinal> = try await runner.run(
            system: "test", initialUser: "start",
            finalSchema: JSONSchema(json: "{\"value\":\"number\"}"),
            tools: ToolRegistry(tools: [EchoTool()]), provider: stub)

        #expect(result.value.value == 9)
        #expect(stub.turnCount == 2)
        #expect(result.calls.count == 2)
        // Turn 2's message history carries the assistant tool_call + the tool result.
        #expect(stub.lastMessages.contains { $0.role == .assistant && $0.toolCalls?.isEmpty == false })
        #expect(stub.lastMessages.contains { $0.role == .tool && $0.content == "\"echo-result\"" })
    }

    @Test func nativeLaneProviderFailurePreservesDiagnostic() async throws {
        let stub = NativeToolStub()
        stub.failFirstTurnWith = .transport("HTTP 400: bad tools")
        let runner = ToolLoopRunner()
        do {
            let _: ToolLoopResult<DummyFinal> = try await runner.run(
                system: "t", initialUser: "u", finalSchema: JSONSchema(json: "{}"),
                tools: ToolRegistry(tools: [EchoTool()]), provider: stub)
            Issue.record("expected throw")
        } catch let ToolLoopError.providerFailedWithMessage(calls, message) {
            #expect(calls.count == 1)
            #expect(message == "HTTP 400: bad tools")
        }
    }
}

private struct EchoTool: CoachTool {
    var descriptor: ToolDescriptor {
        ToolDescriptor(name: "convert_test", description: "test tool", argsSchemaJSON: "{}")
    }
    func run(argsJSON: String) -> String { "\"echo-result\"" }
}

private final class NativeToolStub: LLMProvider, @unchecked Sendable {
    var capabilities: ProviderCapabilities { .init(structuredOutput: .jsonObject, toolCalling: .native) }
    private(set) var turnCount = 0
    private(set) var lastMessages: [ToolChatMessage] = []
    var failFirstTurnWith: LLMError?

    func complete<Value: Decodable & Sendable>(system: String, user: String, schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.unsupported("native stub: use completeToolTurn")
    }
    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String, image: ImagePayload,
                                                        schema: JSONSchema, as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
    func completeToolTurn<Final: Decodable & Sendable>(
        system: String, messages: [ToolChatMessage], tools: [ToolDescriptor],
        finalSchema: JSONSchema, as type: Final.Type
    ) async throws -> NativeToolTurnResult<Final> {
        turnCount += 1
        lastMessages = messages
        if turnCount == 1, let failure = failFirstTurnWith { throw failure }
        if turnCount == 1 {
            return NativeToolTurnResult(
                turn: .toolCalls([NativeToolCall(id: "c1", name: "convert_test", argumentsJSON: "{}")]),
                inputTokens: 3, outputTokens: 4, cachedTokens: 0)
        }
        let value = try JSONDecoder().decode(Final.self, from: Data(#"{"value":9}"#.utf8))
        return NativeToolTurnResult(turn: .final(value), inputTokens: 1, outputTokens: 2, cachedTokens: 0)
    }
}
