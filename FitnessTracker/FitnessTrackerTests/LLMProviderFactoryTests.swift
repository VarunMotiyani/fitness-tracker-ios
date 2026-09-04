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

        let vertex = try LLMProviderFactory.make(kind: .vertexAI,
            baseURL: "https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google/models/",
            apiKey: "token", modelID: "gemini-2.0-flash")
        #expect(vertex is VertexAIProvider)

        let bedrockCreds = "{\"accessKeyId\":\"AKIA...\",\"secretAccessKey\":\"secret\"}"
        let bedrock = try LLMProviderFactory.make(kind: .bedrock, baseURL: "us-east-1", apiKey: bedrockCreds, modelID: "anthropic.claude-3-sonnet")
        #expect(bedrock is BedrockProvider)
    }

    @Test func missingConfigThrows() {
        #expect(throws: LLMProviderFactory.FactoryError.invalidBaseURL) {
            _ = try LLMProviderFactory.make(kind: .openAICompatible, baseURL: nil, apiKey: nil, modelID: "m")
        }
        #expect(throws: LLMProviderFactory.FactoryError.missingAPIKey) {
            _ = try LLMProviderFactory.make(kind: .gemini, baseURL: nil, apiKey: nil, modelID: "m")
        }
        #expect(throws: LLMProviderFactory.FactoryError.invalidBaseURL) {
            _ = try LLMProviderFactory.make(kind: .vertexAI, baseURL: nil, apiKey: "token", modelID: "m")
        }
        #expect(throws: LLMProviderFactory.FactoryError.missingAPIKey) {
            _ = try LLMProviderFactory.make(kind: .vertexAI, baseURL: "https://x.googleapis.com/", apiKey: nil, modelID: "m")
        }
        #expect(throws: LLMProviderFactory.FactoryError.missingRegion) {
            _ = try LLMProviderFactory.make(kind: .bedrock, baseURL: nil, apiKey: "{}", modelID: "m")
        }
        #expect(throws: LLMProviderFactory.FactoryError.missingAPIKey) {
            _ = try LLMProviderFactory.make(kind: .bedrock, baseURL: "us-east-1", apiKey: nil, modelID: "m")
        }
        #expect(throws: LLMProviderFactory.FactoryError.malformedCredentials) {
            _ = try LLMProviderFactory.make(kind: .bedrock, baseURL: "us-east-1", apiKey: "not json", modelID: "m")
        }
    }

    @Test func schemelessBaseURLThrowsInvalidBaseURL() {
        #expect(throws: LLMProviderFactory.FactoryError.invalidBaseURL) {
            _ = try LLMProviderFactory.make(kind: .openAICompatible,
                baseURL: "api.openai.com/v1", apiKey: "k", modelID: "m")
        }
    }
}
