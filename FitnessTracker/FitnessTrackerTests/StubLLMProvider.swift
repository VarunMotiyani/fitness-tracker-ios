import Foundation
import LLMKit

final class StubLLMProvider: LLMProvider, @unchecked Sendable {
    var responses: [Result<String, LLMError>]
    var inputTokens = 10
    var outputTokens = 20
    private(set) var callCount = 0
    private(set) var lastUser = ""

    init(responses: [Result<String, LLMError>]) { self.responses = responses }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        callCount += 1
        lastUser = user
        guard !responses.isEmpty else { throw LLMError.emptyResponse }
        switch responses.removeFirst() {
        case .failure(let e): throw e
        case .success(let json):
            let data = Data(json.utf8)
            let value = try JSONDecoder().decode(Value.self, from: data)
            return LLMResult(value: value, inputTokens: inputTokens, outputTokens: outputTokens,
                             cachedTokens: 0, rawJSON: json)
        }
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}
