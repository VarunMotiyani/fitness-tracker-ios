import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct LLMProviderFactoryTests {
    @Test func buildsEachKind() throws {
        let oai = try LLMProviderFactory.make(kind: .openAICompatible,
            baseURL: "https://api.example.com/v1", apiKey: "k", modelID: "m")
        #expect(oai is OpenAICompatibleProvider)

        let gem = try LLMProviderFactory.make(kind: .gemini, baseURL: nil, apiKey: "k", modelID: "m")
        #expect(gem is GeminiProvider)

        let od = try LLMProviderFactory.make(kind: .appleOnDevice, baseURL: nil, apiKey: nil, modelID: "")
        #expect(od is FoundationModelsProvider)
    }

    @Test func missingConfigThrows() {
        #expect(throws: LLMProviderFactory.FactoryError.invalidBaseURL) {
            _ = try LLMProviderFactory.make(kind: .openAICompatible, baseURL: nil, apiKey: nil, modelID: "m")
        }
        #expect(throws: LLMProviderFactory.FactoryError.missingAPIKey) {
            _ = try LLMProviderFactory.make(kind: .gemini, baseURL: nil, apiKey: nil, modelID: "m")
        }
    }

    @Test func schemelessBaseURLThrowsInvalidBaseURL() {
        #expect(throws: LLMProviderFactory.FactoryError.invalidBaseURL) {
            _ = try LLMProviderFactory.make(kind: .openAICompatible,
                baseURL: "api.openai.com/v1", apiKey: "k", modelID: "m")
        }
    }
}
