import Testing
import Foundation
@testable import FitnessTracker

/// See `AWSSigV4Signer`'s doc comment for why these are structural/
/// differential tests rather than assertions against a memorized AWS
/// "golden" signature constant.
struct AWSSigV4SignerTests {
    private func makeRequest() -> (URLRequest, Data) {
        var request = URLRequest(url: URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/model/test-model/converse")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Data("{\"messages\":[]}".utf8)
        request.httpBody = body
        return (request, body)
    }

    @Test func addsAuthorizationAndDateHeaders() throws {
        let (request, body) = makeRequest()
        let signed = AWSSigV4Signer.sign(
            request: request, body: body,
            accessKeyId: "AKIDEXAMPLE", secretAccessKey: "secret", sessionToken: nil,
            region: "us-east-1", service: "bedrock")

        let auth = try #require(signed.value(forHTTPHeaderField: "Authorization"))
        #expect(auth.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/"))
        #expect(auth.contains("/us-east-1/bedrock/aws4_request"))
        #expect(auth.contains("SignedHeaders="))
        #expect(auth.contains("Signature="))
        #expect(signed.value(forHTTPHeaderField: "X-Amz-Date") != nil)
    }

    @Test func includesSessionTokenHeaderWhenProvided() {
        let (request, body) = makeRequest()
        let signed = AWSSigV4Signer.sign(
            request: request, body: body,
            accessKeyId: "AKIDEXAMPLE", secretAccessKey: "secret", sessionToken: "sess-tok",
            region: "us-east-1", service: "bedrock")
        #expect(signed.value(forHTTPHeaderField: "X-Amz-Security-Token") == "sess-tok")
    }

    @Test func signingIsDeterministicForIdenticalInputs() {
        let (request, body) = makeRequest()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = AWSSigV4Signer.sign(request: request, body: body,
            accessKeyId: "AKID", secretAccessKey: "secret", sessionToken: nil,
            region: "us-east-1", service: "bedrock", date: date)
        let second = AWSSigV4Signer.sign(request: request, body: body,
            accessKeyId: "AKID", secretAccessKey: "secret", sessionToken: nil,
            region: "us-east-1", service: "bedrock", date: date)
        #expect(first.value(forHTTPHeaderField: "Authorization") == second.value(forHTTPHeaderField: "Authorization"))
    }

    @Test func changingSecretKeyChangesSignature() {
        let (request, body) = makeRequest()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = AWSSigV4Signer.sign(request: request, body: body,
            accessKeyId: "AKID", secretAccessKey: "secretA", sessionToken: nil,
            region: "us-east-1", service: "bedrock", date: date)
        let b = AWSSigV4Signer.sign(request: request, body: body,
            accessKeyId: "AKID", secretAccessKey: "secretB", sessionToken: nil,
            region: "us-east-1", service: "bedrock", date: date)
        #expect(a.value(forHTTPHeaderField: "Authorization") != b.value(forHTTPHeaderField: "Authorization"))
    }

    @Test func changingBodyChangesSignature() {
        let (request, _) = makeRequest()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let bodyA = Data("{\"a\":1}".utf8)
        let bodyB = Data("{\"a\":2}".utf8)
        let a = AWSSigV4Signer.sign(request: request, body: bodyA,
            accessKeyId: "AKID", secretAccessKey: "secret", sessionToken: nil,
            region: "us-east-1", service: "bedrock", date: date)
        let b = AWSSigV4Signer.sign(request: request, body: bodyB,
            accessKeyId: "AKID", secretAccessKey: "secret", sessionToken: nil,
            region: "us-east-1", service: "bedrock", date: date)
        #expect(a.value(forHTTPHeaderField: "Authorization") != b.value(forHTTPHeaderField: "Authorization"))
    }

    @Test func changingRegionChangesSignature() {
        let (request, body) = makeRequest()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = AWSSigV4Signer.sign(request: request, body: body,
            accessKeyId: "AKID", secretAccessKey: "secret", sessionToken: nil,
            region: "us-east-1", service: "bedrock", date: date)
        let b = AWSSigV4Signer.sign(request: request, body: body,
            accessKeyId: "AKID", secretAccessKey: "secret", sessionToken: nil,
            region: "eu-west-1", service: "bedrock", date: date)
        #expect(a.value(forHTTPHeaderField: "Authorization") != b.value(forHTTPHeaderField: "Authorization"))
    }
}
