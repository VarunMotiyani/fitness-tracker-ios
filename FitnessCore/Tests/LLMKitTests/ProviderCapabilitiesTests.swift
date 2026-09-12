import Testing
import Foundation
@testable import LLMKit

private struct BareProvider: LLMProvider {
    func complete<Value: Decodable & Sendable>(system: String, user: String, schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.transport("unused")
    }
    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String, image: ImagePayload,
                                                        schema: JSONSchema, as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}

private struct DummyDTO: Decodable, Sendable, Equatable { let ok: Bool }

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
        // api.openai.com gets the native tool lane; other endpoints stay on the prompt loop.
        #expect(ProviderCapabilities.openAICompatibleDefault(host: "api.openai.com").toolCalling == .native)
        #expect(ProviderCapabilities.openAICompatibleDefault(host: "api.groq.com").toolCalling == .viaPrompt)
    }

    @Test func namedDefaults() {
        #expect(ProviderCapabilities.promptOnly == ProviderCapabilities(structuredOutput: .promptOnly, toolCalling: .viaPrompt))
        #expect(ProviderCapabilities.googleResponseSchema.structuredOutput == .nativeJSONSchema)
        #expect(ProviderCapabilities.googleResponseSchema.toolCalling == .native)
    }

    @Test func protocolDefaultIsPromptOnly() {
        #expect(BareProvider().capabilities == .promptOnly)
    }

    @Test func overridingReplacesOnlyGivenFields() {
        let base = ProviderCapabilities(structuredOutput: .jsonObject, toolCalling: .viaPrompt)
        #expect(base.overriding(toolCalling: .native) == ProviderCapabilities(structuredOutput: .jsonObject, toolCalling: .native))
        #expect(base.overriding() == base)
    }

    @Test func completeToolTurnDefaultThrowsUnsupported() async {
        await #expect(throws: LLMError.unsupported("native tool calling")) {
            let _: NativeToolTurnResult<DummyDTO> = try await BareProvider().completeToolTurn(
                system: "s", messages: [], tools: [], finalSchema: JSONSchema(json: "{}"), as: DummyDTO.self)
        }
    }
}
