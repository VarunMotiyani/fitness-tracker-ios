import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct OpenRouterProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    @Test func sendsOpenRouterEndpointHeadersAndJSONMode() async throws {
        let captured = Locked<URLRequest?>(nil)
        let session = StubURLProtocol.session { request in
            captured.set(request)
            let body = #"{"choices":[{"message":{"content":"{\"ok\":true}"}}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        let provider = OpenRouterProvider(apiKey: "sk-or-test", modelID: "qwen/qwen-2.5-7b-instruct",
                                          session: session)
        let result: LLMResult<Dummy> = try await provider.complete(
            system: "Return JSON.", user: "hi", schema: JSONSchema(json: #"{"ok":"boolean"}"#),
            as: Dummy.self)

        #expect(result.value == Dummy(ok: true))
        let request = try #require(captured.get())
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == OpenRouterProvider.defaultHTTPReferer)
        #expect(request.value(forHTTPHeaderField: "X-Title") == OpenRouterProvider.defaultXTitle)

        let body = try #require(request.capturedBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let format = try #require(object["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_object")
    }

    @Test func parsesModelList() throws {
        let data = Data(#"{"data":[{"id":"qwen/qwen3-8b","name":"Qwen 3 8B","context_length":32768,"pricing":{"prompt":"0.0000001","completion":"0.0000004"}}]}"#.utf8)
        let models = try OpenRouterProvider.decodeModels(data)
        let model = try #require(models.first)
        #expect(model.id == "qwen/qwen3-8b")
        #expect(model.name == "Qwen 3 8B")
        #expect(model.contextLength == 32768)
        #expect(model.promptPrice == 0.0000001)
        #expect(model.completionPrice == 0.0000004)
    }

    @Test func modelListFailureDoesNotAffectChatProvider() async throws {
        let session = StubURLProtocol.session { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data("offline".utf8))
        }
        await #expect(throws: LLMError.self) {
            _ = try await OpenRouterProvider.fetchModels(session: session)
        }
    }

    @Test func factoryRoutesOpenRouterWithoutAUserSuppliedBaseURL() throws {
        let provider = try LLMProviderFactory.make(
            kind: .openRouter, baseURL: nil, apiKey: nil, modelID: "qwen/qwen3-8b")
        #expect(provider is OpenRouterProvider)
        #expect(provider.capabilities.structuredOutput == .jsonObject)
        #expect(provider.capabilities.toolCalling == .viaPrompt)
    }
}
