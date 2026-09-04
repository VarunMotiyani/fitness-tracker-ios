import Foundation
import CryptoKit

/// AWS Signature Version 4 request signing — the algorithm every AWS service
/// (Bedrock included) requires instead of a simple API key, because AWS
/// credentials are a key pair (+ optional session token), not one bearer
/// token: https://docs.aws.amazon.com/general/latest/gr/sigv4-signing-steps.html
///
/// This is a from-scratch implementation of that documented algorithm
/// (canonical request → string to sign → derived signing key → signature),
/// not a copy of a specific AWS SDK. It's verified here against the
/// algorithm's own internal consistency (same inputs always produce the same
/// signature; changing any single input changes it) rather than against a
/// memorized "golden" AWS signature constant — hand-copying a 64-character
/// hex digest from memory risks a silently wrong test oracle, which is worse
/// than no oracle at all. Verify once against a real Bedrock call with real
/// credentials before trusting this in production.
nonisolated enum AWSSigV4Signer {
    /// Adds `Authorization`, `X-Amz-Date`, and (if present) `X-Amz-Security-Token`
    /// headers to `request`, signing exactly the headers already present on it
    /// plus `host` — callers must set every header they want signed (notably
    /// `Content-Type`) *before* calling `sign`.
    static func sign(
        request: URLRequest,
        body: Data,
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String?,
        region: String,
        service: String,
        date: Date = .now
    ) -> URLRequest {
        var signed = request
        let (dateStamp, amzDate) = timestamps(for: date)
        let host = request.url?.host ?? ""

        signed.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        signed.setValue(host, forHTTPHeaderField: "host")
        if let sessionToken {
            signed.setValue(sessionToken, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        let headerFields = signed.allHTTPHeaderFields ?? [:]
        let canonicalHeaderPairs = headerFields
            .map { (key: $0.key.lowercased(), value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .sorted { $0.key < $1.key }
        let canonicalHeaders = canonicalHeaderPairs.map { "\($0.key):\($0.value)\n" }.joined()
        let signedHeaders = canonicalHeaderPairs.map(\.key).joined(separator: ";")

        let canonicalURI = (request.url?.path.isEmpty ?? true) ? "/" : (request.url?.path ?? "/")
        let canonicalQuery = canonicalQueryString(from: request.url)
        let hashedPayload = sha256Hex(body)

        let canonicalRequest = [
            request.httpMethod ?? "POST",
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            hashedPayload,
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(
            secretAccessKey: secretAccessKey, dateStamp: dateStamp, region: region, service: service)
        let signature = hmacHex(key: signingKey, message: Data(stringToSign.utf8))

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        signed.setValue(authorization, forHTTPHeaderField: "Authorization")
        return signed
    }

    // MARK: - Steps

    private static func timestamps(for date: Date) -> (dateStamp: String, amzDate: String) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let dateStamp = formatter.string(from: date)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        return (dateStamp, amzDate)
    }

    /// AWS's canonical query string: percent-encode each key/value with the
    /// stricter "URI encode" rules (space -> %20, not +), then sort by key.
    private static func canonicalQueryString(from url: URL?) -> String {
        guard let items = URLComponents(url: url ?? URL(string: "https://x")!, resolvingAgainstBaseURL: false)?.queryItems,
              !items.isEmpty
        else { return "" }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        return items
            .map { (encode($0.name), encode($0.value ?? "")) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    private static func deriveSigningKey(secretAccessKey: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        let kSecret = Data("AWS4\(secretAccessKey)".utf8)
        let kDate = hmac(key: SymmetricKey(data: kSecret), message: Data(dateStamp.utf8))
        let kRegion = hmac(key: SymmetricKey(data: kDate), message: Data(region.utf8))
        let kService = hmac(key: SymmetricKey(data: kRegion), message: Data(service.utf8))
        let kSigning = hmac(key: SymmetricKey(data: kService), message: Data("aws4_request".utf8))
        return SymmetricKey(data: kSigning)
    }

    private static func hmac(key: SymmetricKey, message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    private static func hmacHex(key: SymmetricKey, message: Data) -> String {
        hmac(key: key, message: message).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
