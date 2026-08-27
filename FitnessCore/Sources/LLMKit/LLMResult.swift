public enum LLMCallType: String, Codable, Sendable, CaseIterable {
    case weeklyPlan, adjust, finalize, swap, feedback, inbody
}

public struct LLMResult<Value: Decodable & Sendable>: Sendable {
    public let value: Value
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int
    public let rawJSON: String
    public init(value: Value, inputTokens: Int, outputTokens: Int,
                cachedTokens: Int, rawJSON: String) {
        self.value = value
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.rawJSON = rawJSON
    }
}
