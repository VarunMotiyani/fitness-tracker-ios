import Testing
import Foundation
@testable import LLMKit

private struct DummyFinal: Codable, Sendable, Equatable {
    let answer: String
}

@Suite struct ToolLoopSchemaTests {
    @Test func decodesToolCallTurn() throws {
        let json = """
        {"decision":"tool_call","toolCall":{"name":"get_recovery_status","argsJSON":"{}"}}
        """.data(using: .utf8)!
        let turn = try JSONDecoder().decode(ToolLoopTurn<DummyFinal>.self, from: json)
        guard case .toolCall(let request) = turn else {
            Issue.record("expected .toolCall"); return
        }
        #expect(request.name == "get_recovery_status")
    }

    @Test func decodesFinalTurn() throws {
        let json = """
        {"decision":"final","final":{"answer":"done"}}
        """.data(using: .utf8)!
        let turn = try JSONDecoder().decode(ToolLoopTurn<DummyFinal>.self, from: json)
        guard case .final(let value) = turn else {
            Issue.record("expected .final"); return
        }
        #expect(value.answer == "done")
    }

    @Test func encodesToolCallTurnRoundTrip() throws {
        let turn = ToolLoopTurn<DummyFinal>.toolCall(ToolCallRequest(name: "plate_math", argsJSON: "{\"targetLoadKg\":100}"))
        let data = try JSONEncoder().encode(turn)
        let decoded = try JSONDecoder().decode(ToolLoopTurn<DummyFinal>.self, from: data)
        guard case .toolCall(let request) = decoded else {
            Issue.record("expected .toolCall"); return
        }
        #expect(request.name == "plate_math")
    }

    @Test func unknownDecisionThrows() {
        let json = """
        {"decision":"nonsense"}
        """.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ToolLoopTurn<DummyFinal>.self, from: json)
        }
    }

    @Test func schemaDescribesEveryTool() {
        let tools = [
            ToolDescriptor(name: "get_recovery_status", description: "Live per-muscle fatigue.", argsSchemaJSON: "{\"muscle\":\"string?\"}"),
            ToolDescriptor(name: "plate_math", description: "Plates for a target load.", argsSchemaJSON: "{\"targetLoadKg\":\"number\"}"),
        ]
        let schema = ToolLoopTurn<DummyFinal>.schema(
            finalSchema: JSONSchema(json: "{\"answer\":\"string\"}"), tools: tools)
        #expect(schema.json.contains("get_recovery_status"))
        #expect(schema.json.contains("plate_math"))
        #expect(schema.json.contains("\"decision\""))
    }
}
