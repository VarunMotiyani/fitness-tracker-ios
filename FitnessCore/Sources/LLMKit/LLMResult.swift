public enum LLMCallType: String, Codable, Sendable, CaseIterable {
    case weeklyPlan, adjust, finalize, swap, feedback, inbody
}

public struct LLMResult<Value: Decodable & Sendable>: Sendable {
    public let value: Value
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int
    public let rawJSON: String
    /// Set by `ResilientProvider` when the primary failed and this result came
    /// from the configured fallback provider.
    public var usedFallback: Bool
    public init(value: Value, inputTokens: Int, outputTokens: Int,
                cachedTokens: Int, rawJSON: String, usedFallback: Bool = false) {
        self.value = value
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.rawJSON = rawJSON
        self.usedFallback = usedFallback
    }
}
