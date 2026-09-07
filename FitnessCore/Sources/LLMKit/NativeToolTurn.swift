/// Types for the native tool-calling lane — used when a provider's
/// `capabilities.toolCalling == .native`, so the model drives tool use through
/// the provider's real function-calling API and a proper message history
/// instead of a hand-rolled JSON envelope.

/// One tool invocation the model asked for.
public struct NativeToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// A provider-neutral chat message carried across native tool-loop turns.
public struct ToolChatMessage: Sendable {
    public enum Role: String, Sendable {
        case system, user, assistant, tool
    }

    public let role: Role
    /// Text content. Nil for an assistant message whose only payload is
    /// `toolCalls`.
    public let content: String?
    /// Set on a `.tool` message: which `NativeToolCall.id` this result answers.
    public let toolCallID: String?
    /// Set on an `.assistant` message that requested tools.
    public let toolCalls: [NativeToolCall]?

    public init(role: Role, content: String? = nil,
                toolCallID: String? = nil, toolCalls: [NativeToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }
}

/// The outcome of one native turn: either the model asked for tools, or it
/// produced its final schema-conformant answer.
public enum NativeToolTurn<Final: Decodable & Sendable>: Sendable {
    case toolCalls([NativeToolCall])
    case final(Final)
}

/// One native turn plus its token usage, for call-granular billing (mirrors
/// `LLMResult`'s usage fields).
public struct NativeToolTurnResult<Final: Decodable & Sendable>: Sendable {
    public let turn: NativeToolTurn<Final>
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int

    public init(turn: NativeToolTurn<Final>, inputTokens: Int, outputTokens: Int, cachedTokens: Int) {
        self.turn = turn
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
    }
}
