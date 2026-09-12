/// Types for the native tool-calling lane — used when a provider's
/// `capabilities.toolCalling == .native`, so the model drives tool use through
/// the provider's real function-calling API and a proper message history
/// instead of a hand-rolled JSON envelope.

/// One tool invocation the model asked for.
public struct NativeToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String
    /// Opaque provider metadata that must be returned with a follow-up turn.
    /// Gemini 3 uses this for its encrypted thought signature.
    public let thoughtSignature: String?

    public init(id: String, name: String, argumentsJSON: String, thoughtSignature: String? = nil) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.thoughtSignature = thoughtSignature
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
    /// Set on a `.tool` message: the function name associated with the call.
    /// Some providers (including Gemini) require both the name and id.
    public let toolName: String?
    /// Set on an `.assistant` message that requested tools.
    public let toolCalls: [NativeToolCall]?

    public init(role: Role, content: String? = nil,
                toolCallID: String? = nil, toolName: String? = nil,
                toolCalls: [NativeToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolName = toolName
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
    /// Set by `ResilientProvider` when this turn came from the fallback provider.
    public var usedFallback: Bool

    public init(turn: NativeToolTurn<Final>, inputTokens: Int, outputTokens: Int,
                cachedTokens: Int, usedFallback: Bool = false) {
        self.turn = turn
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.usedFallback = usedFallback
    }
}
