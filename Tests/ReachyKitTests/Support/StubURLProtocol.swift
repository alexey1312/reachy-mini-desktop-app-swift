import Foundation

/// Serves canned HTTP responses to a `URLSession` injected into `RobotConnection`,
/// which is the only way to exercise daemon status codes without a daemon.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        let statusCode: Int
        let body: Data

        init(statusCode: Int, json: String = "{}") {
            self.statusCode = statusCode
            body = Data(json.utf8)
        }
    }

    private nonisolated(unsafe) static var stubs: [String: Stub] = [:]
    private static let lock = NSLock()

    /// Keyed by request path, e.g. `/api/state/full`.
    static func install(_ stubs: [String: Stub]) {
        lock.withLock { Self.stubs = stubs }
    }

    static func reset() {
        lock.withLock { stubs = [:] }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let stub = Self.lock.withLock({ Self.stubs[url.path] }),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
