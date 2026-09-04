import Foundation

public struct ToolDescriptor: Sendable, Equatable {
    public let name: String
    public let description: String
    public let argsSchemaJSON: String
    public init(name: String, description: String, argsSchemaJSON: String) {
        self.name = name
        self.description = description
        self.argsSchemaJSON = argsSchemaJSON
    }
}

public struct ToolCallRequest: Codable, Sendable, Equatable {
    public let name: String
    public let argsJSON: String
    public init(name: String, argsJSON: String) {
        self.name = name
        self.argsJSON = argsJSON
    }
}

/// One turn of the provider-agnostic tool loop (design spec §8): the model
/// either asks to run a tool or gives its final, schema-conformant answer.
/// Implemented as a manual discriminated union over `LLMProvider.complete`'s
/// existing schema-in/value-out contract — no per-provider function-calling
/// dependency, so it behaves identically across DeepSeek/GLM/Kimi/OpenAI-
/// compatible providers regardless of whether each one's native tool-calling
/// support is reliable.
public enum ToolLoopTurn<Final: Codable & Sendable>: Sendable {
    case toolCall(ToolCallRequest)
    case final(Final)

    private enum CodingKeys: String, CodingKey {
        case decision, toolCall, final
    }

    public static func schema(finalSchema: JSONSchema, tools: [ToolDescriptor]) -> JSONSchema {
        let toolLines = tools.map { "    \"\($0.name)\": \($0.argsSchemaJSON) // \($0.description)" }
            .joined(separator: ",\n")
        let json = """
        {
          "decision": "tool_call | final",
          "toolCall": {"name": "one of: \(tools.map(\.name).joined(separator: ", "))", "argsJSON": "string, JSON-encoded args matching the tool's schema"},
          "final": \(finalSchema.json),
          "_tools": {
        \(toolLines)
          }
        }
        """
        return JSONSchema(json: json)
    }
}

extension ToolLoopTurn: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decision = try container.decode(String.self, forKey: .decision)
        switch decision {
        case "tool_call":
            self = .toolCall(try container.decode(ToolCallRequest.self, forKey: .toolCall))
        case "final":
            self = .final(try container.decode(Final.self, forKey: .final))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .decision, in: container,
                debugDescription: "unknown decision '\(decision)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .toolCall(let request):
            try container.encode("tool_call", forKey: .decision)
            try container.encode(request, forKey: .toolCall)
        case .final(let value):
            try container.encode("final", forKey: .decision)
            try container.encode(value, forKey: .final)
        }
    }
}
