public enum LLMError: Error, Sendable, Equatable {
    case visionUnsupported
    case emptyResponse
    case rateLimited
    case transport(String)
    case decoding(String)
    /// A capability the provider/adapter does not implement (e.g. a native
    /// tool turn on an adapter that only does the prompt lane).
    case unsupported(String)
}
