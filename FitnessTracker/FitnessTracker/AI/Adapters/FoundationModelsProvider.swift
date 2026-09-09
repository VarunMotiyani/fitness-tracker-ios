import Foundation
import LLMKit

#if canImport(FoundationModels)
import FoundationModels

/// On-device provider backed by Apple's FoundationModels (`SystemLanguageModel`).
/// Tokens are not reported by the framework, so all token counts are 0.
nonisolated struct FoundationModelsProvider: LLMProvider {
    init() {}

    /// Foundation Models validates the response against the supplied guided
    /// schema. Tool calls remain on the provider-agnostic prompt lane for now.
    var capabilities: ProviderCapabilities {
        ProviderCapabilities(structuredOutput: .nativeJSONSchema, toolCalling: .viaPrompt)
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        guard case .available = SystemLanguageModel.default.availability else {
            throw LLMError.transport("on-device model unavailable")
        }

        let generationSchema: GenerationSchema
        do {
            generationSchema = try Self.generationSchema(from: schema)
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.decoding("schema: \(error)")
        }

        let session = LanguageModelSession(instructions: system)

        let content: GeneratedContent
        do {
            let response = try await session.respond(
                to: user,
                schema: generationSchema,
                includeSchemaInPrompt: false)
            content = response.content
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }

        let rawJSON = content.jsonString

        let value: Value
        do {
            value = try JSONDecoder().decode(Value.self, from: Data(rawJSON.utf8))
        } catch {
            throw LLMError.decoding("content: \(error)")
        }

        return LLMResult(value: value,
                         inputTokens: 0,
                         outputTokens: 0,
                         cachedTokens: 0,
                         rawJSON: rawJSON)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }

    /// Converts the app's provider-neutral JSON schema representation to the
    /// runtime schema Foundation Models uses for guided generation.
    static func generationSchema(from schema: JSONSchema) throws -> GenerationSchema {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(schema.json.utf8))
        } catch {
            throw LLMError.decoding("schema JSON: \(error)")
        }

        let root = try dynamicSchema(name: "Response", value: object)
        do {
            return try GenerationSchema(root: root, dependencies: [])
        } catch {
            throw LLMError.decoding("Foundation Models schema: \(error)")
        }
    }

    private static func dynamicSchema(name: String, value: Any) throws -> DynamicGenerationSchema {
        if let shorthand = value as? String {
            return primitiveSchema(shorthand)
        }

        guard let object = value as? [String: Any] else {
            throw LLMError.decoding("unsupported schema value for '\(name)'")
        }

        if let choices = object["enum"] as? [String], !choices.isEmpty {
            return DynamicGenerationSchema(name: name, anyOf: choices)
        }

        let type = object["type"] as? String
        switch type {
        case "object":
            return try objectSchema(name: name, object: object)
        case "array":
            let itemValue = object["items"] ?? ["type": "string"]
            let itemSchema = try dynamicSchema(name: "\(name)Item", value: itemValue)
            return DynamicGenerationSchema(
                arrayOf: itemSchema,
                minimumElements: object["minItems"] as? Int,
                maximumElements: object["maxItems"] as? Int)
        case "string", "integer", "number", "boolean":
            return primitiveSchema(type ?? "string")
        case "null":
            // DynamicGenerationSchema.null is only available from iOS 26.4;
            // the app's minimum target is iOS 26.0. A nullable field is
            // represented by the containing property's `isOptional` flag.
            return primitiveSchema("string")
        default:
            // Some legacy prompt builders omit `type` and provide only a
            // properties map. Treat that as an object before falling back to
            // a string so old schemas remain usable on-device.
            if object["properties"] != nil {
                return try objectSchema(name: name, object: object)
            }
            return primitiveSchema("string")
        }
    }

    private static func objectSchema(name: String, object: [String: Any]) throws -> DynamicGenerationSchema {
        let properties = object["properties"] as? [String: Any] ?? [:]
        let required = Set(object["required"] as? [String] ?? [])
        let dynamicProperties = try properties.map { propertyName, propertyValue in
            let propertyObject = propertyValue as? [String: Any]
            let description = propertyObject?["description"] as? String
            return DynamicGenerationSchema.Property(
                name: propertyName,
                description: description,
                schema: try dynamicSchema(name: propertyName, value: propertyValue),
                isOptional: !required.contains(propertyName))
        }
        return DynamicGenerationSchema(
            name: name,
            description: object["description"] as? String,
            properties: dynamicProperties)
    }

    private static func primitiveSchema(_ type: String) -> DynamicGenerationSchema {
        switch type {
        case "integer": DynamicGenerationSchema(type: Int.self)
        case "number": DynamicGenerationSchema(type: Double.self)
        case "boolean": DynamicGenerationSchema(type: Bool.self)
        default: DynamicGenerationSchema(type: String.self)
        }
    }
}

#else

/// Fallback when FoundationModels is not part of the SDK for this build.
nonisolated struct FoundationModelsProvider: LLMProvider {
    init() {}

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(structuredOutput: .nativeJSONSchema, toolCalling: .viaPrompt)
    }

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
