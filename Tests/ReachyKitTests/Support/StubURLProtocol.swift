import Foundation

/// Serves canned HTTP responses to a `URLSession` injected into `RobotConnection`,
/// which is the only way to exercise daemon status codes without a daemon.
///
/// Stubs bind to the session that carries them, not to a global table: `swift test
/// --parallel` runs separate suites concurrently, so a shared table lets one suite
/// answer another suite's requests, or wipe them mid-flight. `.serialized` is no
/// defence — it orders tests within one suite and says nothing about the others.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        let statusCode: Int
        let body: Data

        init(statusCode: Int, json: String = "{}") {
            self.statusCode = statusCode
            body = Data(json.utf8)
        }
    }

    /// Routes are keyed by path, optionally narrowed by a query:
    /// `/update/available` answers whatever the query is, while
    /// `/update/available?pre_release=true` answers only that one. The narrower key
    /// wins, so a table can pin one variant and let the bare path cover the rest —
    /// without it, `pre_release=true` and `false` collapse onto a single stub.
    static func makeSession(_ stubs: [String: Stub]) -> URLSession {
        let token = UUID().uuidString
        lock.withLock { sessions[token] = stubs }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: configuration)
    }

    /// What this session was actually asked for, in order. The sealed Wi-Fi payload is
    /// the reason this exists: a test has to be able to prove the password never
    /// appeared in a URL.
    static func requests(for session: URLSession) -> [URLRequest] {
        guard let token = session.configuration.httpAdditionalHeaders?[tokenHeader] as? String else {
            return []
        }
        return lock.withLock { served[token] ?? [] }
    }

    private static let tokenHeader = "X-Stub-Session"
    private nonisolated(unsafe) static var sessions: [String: [String: Stub]] = [:]
    private nonisolated(unsafe) static var served: [String: [URLRequest]] = [:]
    private static let lock = NSLock()

    private static func record(_ request: URLRequest) {
        guard let token = request.value(forHTTPHeaderField: tokenHeader) else { return }
        lock.withLock { served[token, default: []].append(request) }
    }

    private static func stub(for request: URLRequest) -> Stub? {
        guard let token = request.value(forHTTPHeaderField: tokenHeader),
              let url = request.url,
              let table = lock.withLock({ sessions[token] })
        else { return nil }

        if let query = url.query(), let narrow = table["\(url.path)?\(query)"] {
            return narrow
        }
        return table[url.path]
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.record(request)
        guard let url = request.url,
              let stub = Self.stub(for: request),
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
