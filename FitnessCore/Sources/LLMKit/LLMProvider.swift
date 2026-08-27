public protocol LLMProvider: Sendable {
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
