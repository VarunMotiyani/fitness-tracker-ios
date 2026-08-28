import Foundation
import LLMKit

#if canImport(FoundationModels)
import FoundationModels

/// On-device provider backed by Apple's FoundationModels (`SystemLanguageModel`).
/// Tokens are not reported by the framework, so all token counts are 0.
nonisolated struct FoundationModelsProvider: LLMProvider {
    init() {}

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        guard case .available = SystemLanguageModel.default.availability else {
            throw LLMError.transport("on-device model unavailable")
        }

        let prompt = user
            + "\n\nRespond with a single JSON object matching this schema. No prose, no code fences:\n"
            + schema.json
        let session = LanguageModelSession(instructions: system)

        let content: String
        do {
            content = try await session.respond(to: prompt).content
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }

        let cleaned = Self.stripCodeFences(content)

        let value: Value
        do {
            value = try JSONDecoder().decode(Value.self, from: Data(cleaned.utf8))
        } catch {
            throw LLMError.decoding("content: \(error)")
        }

        return LLMResult(value: value,
                         inputTokens: 0,
                         outputTokens: 0,
                         cachedTokens: 0,
                         rawJSON: cleaned)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }

    /// Removes a leading ```/```json fence and a trailing ``` fence, if present.
    private static func stripCodeFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }

        if let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        } else {
            text = String(text.dropFirst(3))
        }

        if let fenceRange = text.range(of: "```", options: .backwards) {
            text = String(text[..<fenceRange.lowerBound])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#else

/// Fallback when FoundationModels is not part of the SDK for this build.
nonisolated struct FoundationModelsProvider: LLMProvider {
    init() {}

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.transport("FoundationModels unavailable in this build")
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}

#endif
