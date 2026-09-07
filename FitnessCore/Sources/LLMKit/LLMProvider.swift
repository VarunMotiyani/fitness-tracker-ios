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

    /// One turn of the native tool-calling lane. A protocol requirement (not
    /// just an extension) so a call through `any LLMProvider` dynamically
    /// dispatches to the adapter's implementation; the extension default lets
    /// conformers that only do the prompt lane skip it.
    func completeToolTurn<Final: Decodable & Sendable>(
        system: String,
        messages: [ToolChatMessage],
        tools: [ToolDescriptor],
        finalSchema: JSONSchema,
        as type: Final.Type
    ) async throws -> NativeToolTurnResult<Final>
}

public extension LLMProvider {
    /// Safe default so test doubles and unknown providers work: the manual
    /// prompt loop always functions. Real adapters override this.
    var capabilities: ProviderCapabilities { .promptOnly }

    /// Default for providers whose `capabilities.toolCalling` is `.viaPrompt`.
    func completeToolTurn<Final: Decodable & Sendable>(
        system: String,
        messages: [ToolChatMessage],
        tools: [ToolDescriptor],
        finalSchema: JSONSchema,
        as type: Final.Type
    ) async throws -> NativeToolTurnResult<Final> {
        throw LLMError.unsupported("native tool calling")
    }
}
