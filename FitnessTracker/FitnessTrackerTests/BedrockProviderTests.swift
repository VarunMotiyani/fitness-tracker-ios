import Testing
import Foundation
@testable import FitnessTracker

struct BedrockProviderTests {
    @Test func parsesCredentialsWithSessionToken() throws {
        let json = "{\"accessKeyId\":\"AKIA123\",\"secretAccessKey\":\"secret\",\"sessionToken\":\"tok\"}"
        let creds = try #require(BedrockProvider.parseCredentials(json))
        #expect(creds.accessKeyId == "AKIA123")
        #expect(creds.secretAccessKey == "secret")
        #expect(creds.sessionToken == "tok")
    }

    @Test func parsesCredentialsWithoutSessionToken() throws {
        let json = "{\"accessKeyId\":\"AKIA123\",\"secretAccessKey\":\"secret\"}"
        let creds = try #require(BedrockProvider.parseCredentials(json))
        #expect(creds.sessionToken == nil)
    }

    @Test func malformedCredentialsJSONReturnsNil() {
        #expect(BedrockProvider.parseCredentials("not json") == nil)
        #expect(BedrockProvider.parseCredentials("{}") == nil)
    }

    @Test func stripCodeFenceRemovesFencedJSON() {
        let fenced = "```json\n{\"a\":1}\n```"
        #expect(BedrockProvider.stripCodeFence(fenced) == "{\"a\":1}")
    }

    @Test func stripCodeFenceLeavesPlainJSONUnchanged() {
        let plain = "{\"a\":1}"
        #expect(BedrockProvider.stripCodeFence(plain) == plain)
    }
}
