public enum LLMError: Error, Sendable, Equatable {
    case visionUnsupported
    case emptyResponse
    case rateLimited
    case transport(String)
    case decoding(String)
}
