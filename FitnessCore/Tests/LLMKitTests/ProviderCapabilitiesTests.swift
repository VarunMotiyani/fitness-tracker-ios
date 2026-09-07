import Testing
import Foundation
@testable import LLMKit

struct ProviderCapabilitiesTests {

    @Test func codableRoundTrip() throws {
        let caps = ProviderCapabilities(structuredOutput: .jsonObject, toolCalling: .native)
        let data = try JSONEncoder().encode(caps)
        let back = try JSONDecoder().decode(ProviderCapabilities.self, from: data)
        #expect(back == caps)
        // Raw-string enum encoding, so the shape is stable across storage.
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["structuredOutput"] as? String == "jsonObject")
        #expect(obj["toolCalling"] as? String == "native")
    }

    @Test func openAICompatibleDefaultBranchesOnOfficialHost() {
        #expect(ProviderCapabilities.openAICompatibleDefault(host: "api.openai.com").structuredOutput == .nativeJSONSchema)
        #expect(ProviderCapabilities.openAICompatibleDefault(host: "api.groq.com").structuredOutput == .jsonObject)
        #expect(ProviderCapabilities.openAICompatibleDefault(host: nil).structuredOutput == .jsonObject)
        // No adapter drives native tools yet.
        #expect(ProviderCapabilities.openAICompatibleDefault(host: "api.openai.com").toolCalling == .viaPrompt)
    }

    @Test func namedDefaults() {
        #expect(ProviderCapabilities.promptOnly == ProviderCapabilities(structuredOutput: .promptOnly, toolCalling: .viaPrompt))
        #expect(ProviderCapabilities.googleResponseSchema.structuredOutput == .nativeJSONSchema)
    }

    @Test func protocolDefaultIsPromptOnly() {
        struct Bare: LLMProvider {
            func complete<Value: Decodable & Sendable>(system: String, user: String, schema: JSONSchema,
                                                       as type: Value.Type) async throws -> LLMResult<Value> {
                throw LLMError.transport("unused")
            }
            func completeWithImage<Value: Decodable & Sendable>(system: String, user: String, image: ImagePayload,
                                                                schema: JSONSchema, as type: Value.Type) async throws -> LLMResult<Value> {
                throw LLMError.visionUnsupported
            }
        }
        #expect(Bare().capabilities == .promptOnly)
    }
}
