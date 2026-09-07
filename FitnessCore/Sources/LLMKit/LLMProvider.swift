public protocol LLMProvider: Sendable {
    /// What this provider can actually be driven to do (structured-output mode,
    /// tool-calling lane). The runner reads this instead of guessing.
    var capabilities: ProviderCapabilities { get }

    func complete<Value: Decodable & Sendable>(
        system: String,
        user: String,
        schema: JSONSchema,
        as type: Value.Type
    ) async throws -> LLMResult<Value>

    func completeWithImage<Value: Decodable & Sendable>(
        system: String,
        user: String,
        image: ImagePayload,
        schema: JSONSchema,
        as type: Value.Type
    ) async throws -> LLMResult<Value>
}

public extension LLMProvider {
    /// Safe default so test doubles and unknown providers work: the manual
    /// prompt loop always functions. Real adapters override this.
    var capabilities: ProviderCapabilities { .promptOnly }
}
