import Foundation

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var tokenHandlers: [String: Handler] = [:]
    private static var _handler: Handler?

    /// Process-global handler. Assigning it here stages the handler; the next
    /// `session()` call snapshots it against that session's private token so
    /// concurrently-running suites cannot observe each other's handler.
    nonisolated(unsafe) static var handler: Handler? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    private static let tokenHeader = "X-Stub-Session-Token"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let resolved: Handler? = {
            if let token = request.value(forHTTPHeaderField: Self.tokenHeader) {
                return Self.lock.withLock { Self.tokenHandlers[token] ?? Self._handler }
            }
            return Self.handler
        }()
        guard let resolved else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (response, data) = try resolved(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let token = UUID().uuidString
        lock.withLock { tokenHandlers[token] = _handler }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: config)
    }
}
