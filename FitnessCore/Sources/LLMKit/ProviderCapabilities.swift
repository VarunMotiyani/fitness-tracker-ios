/// What a provider can actually be driven to do, so callers stop guessing at
/// runtime. Values describe the behaviour the adapter *implements today* — not
/// the provider's theoretical API surface. Upgrade a field when the adapter
/// gains the matching path (e.g. `toolCalling` flips to `.native` once the
/// adapter implements a native tool turn).
public struct ProviderCapabilities: Sendable, Equatable, Codable {
    /// How structured output is enforced.
    public enum StructuredOutput: String, Sendable, Codable {
        /// Provider enforces a real JSON Schema server-side (OpenAI strict
        /// `json_schema`, Gemini `responseSchema`, Apple guided generation).
        case nativeJSONSchema
        /// Provider guarantees valid JSON but not a schema (`json_object`).
        case jsonObject
        /// No server-side JSON guarantee; rely on the prompt plus local decode.
        case promptOnly
    }

    /// How multi-step tool use is executed.
    public enum ToolCalling: String, Sendable, Codable {
        /// Provider has a function/tool API the runner drives with a real
        /// message history.
        case native
        /// No reliable native tools; use the manual prompt-envelope loop.
        case viaPrompt
    }

    public var structuredOutput: StructuredOutput
    public var toolCalling: ToolCalling

    public init(structuredOutput: StructuredOutput, toolCalling: ToolCalling) {
        self.structuredOutput = structuredOutput
        self.toolCalling = toolCalling
    }
}

public extension ProviderCapabilities {
    /// The always-works baseline: prompt-embedded schema, manual tool loop.
    /// Used as the `LLMProvider` protocol default so test stubs need no change.
    static let promptOnly = ProviderCapabilities(structuredOutput: .promptOnly, toolCalling: .viaPrompt)

    /// OpenAI-compatible endpoints: `api.openai.com` enforces strict
    /// `json_schema`; everything else (Groq, Together, Fireworks, …) is only
    /// trusted for `json_object`. No adapter drives native tools yet.
    static func openAICompatibleDefault(host: String?) -> ProviderCapabilities {
        host == "api.openai.com"
            ? ProviderCapabilities(structuredOutput: .nativeJSONSchema, toolCalling: .viaPrompt)
            : ProviderCapabilities(structuredOutput: .jsonObject, toolCalling: .viaPrompt)
    }

    /// Gemini / Vertex AI: `responseSchema` is enforced server-side.
    static let googleResponseSchema = ProviderCapabilities(structuredOutput: .nativeJSONSchema, toolCalling: .viaPrompt)
}
