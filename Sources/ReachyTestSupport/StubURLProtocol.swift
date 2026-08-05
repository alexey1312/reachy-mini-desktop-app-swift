import Foundation

/// Serves canned HTTP responses to a `URLSession` injected into `RobotConnection`,
/// which is the only way to exercise daemon status codes without a daemon.
///
/// Stubs bind to the session that carries them, not to a global table: `swift test
/// --parallel` runs separate suites concurrently, so a shared table lets one suite
/// answer another suite's requests, or wipe them mid-flight. `.serialized` is no
/// defence — it orders tests within one suite and says nothing about the others.
/// `@unchecked Sendable` for the streaming case alone: a chunked response is
/// delivered from a task, which has to hand `self` back to the URL loading
/// system. `URLProtocol` is not `Sendable`, and the instance is confined to one
/// request either way.
public final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    public struct Stub: Sendable {
        let statusCode: Int
        let body: Data
        /// Delivered one at a time, so a caller reading with `URLSession.bytes`
        /// sees them arrive rather than all at once.
        let chunks: [Data]
        /// Whether the response stays open after the last chunk — what a
        /// server-sent-event stream does between events, and the only way to
        /// exercise a read timeout.
        let staysOpen: Bool

        public init(statusCode: Int, json: String = "{}") {
            self.statusCode = statusCode
            body = Data(json.utf8)
            chunks = []
            staysOpen = false
        }

        /// A server-sent-event stream. Each line is delivered as its own chunk,
        /// newline included.
        public init(statusCode: Int, lines: [String], staysOpen: Bool = false) {
            self.statusCode = statusCode
            body = Data()
            chunks = lines.map { Data("\($0)\n".utf8) }
            self.staysOpen = staysOpen
        }
    }

    /// Routes are keyed by path, optionally narrowed by a query:
    /// `/update/available` answers whatever the query is, while
    /// `/update/available?pre_release=true` answers only that one. The narrower key
    /// wins, so a table can pin one variant and let the bare path cover the rest —
    /// without it, `pre_release=true` and `false` collapse onto a single stub.
    public static func makeSession(_ stubs: [String: Stub]) -> URLSession {
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
    public static func requests(for session: URLSession) -> [URLRequest] {
        served(for: session).map(\.request)
    }

    /// Sent bodies, in the same order as `requests(for:)`.
    ///
    /// `URLRequest.httpBody` is nil by the time a protocol sees an upload — the
    /// payload arrives as a stream — so it is drained here. `POST /apps/install`
    /// is the reason: the daemon stores that body as the app's metadata, and only
    /// the bytes on the wire prove nothing was dropped on the way.
    public static func bodies(for session: URLSession) -> [Data] {
        served(for: session).map(\.body)
    }

    private struct Served {
        let request: URLRequest
        let body: Data
    }

    private static func served(for session: URLSession) -> [Served] {
        guard let token = session.configuration.httpAdditionalHeaders?[tokenHeader] as? String else {
            return []
        }
        return lock.withLock { served[token] ?? [] }
    }

    private let streamQueue = DispatchQueue(label: "StubURLProtocol.stream")
    private let stopFlag = NSLock()
    private var stopped = false

    private static let tokenHeader = "X-Stub-Session"
    private nonisolated(unsafe) static var sessions: [String: [String: Stub]] = [:]
    private nonisolated(unsafe) static var served: [String: [Served]] = [:]
    private static let lock = NSLock()

    private static func record(_ request: URLRequest) {
        guard let token = request.value(forHTTPHeaderField: tokenHeader) else { return }
        let body = request.httpBody ?? request.httpBodyStream.map(drain) ?? Data()
        lock.withLock { served[token, default: []].append(Served(request: request, body: body)) }
    }

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
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

    override public static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override public static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override public func startLoading() {
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

        guard !stub.chunks.isEmpty || stub.staysOpen else {
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // Off the loading thread, and one chunk at a time: a stream delivered in a
        // single `didLoad` would let a reader see the whole thing before it ever
        // suspends, which is the one thing a stream test must not do.
        //
        // A `DispatchQueue` rather than a `Task`: handing this instance back to
        // the URL loading system from inside a task is exactly the capture Swift 6
        // refuses, and the queue's `@Sendable` closure is satisfied by the
        // `@unchecked` conformance above.
        streamQueue.async { [self] in
            for chunk in stub.chunks {
                Thread.sleep(forTimeInterval: 0.005)
                guard !isStopped else { return }
                client?.urlProtocol(self, didLoad: chunk)
            }
            guard !stub.staysOpen, !isStopped else { return }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override public func stopLoading() {
        stopFlag.withLock { stopped = true }
    }

    private var isStopped: Bool {
        stopFlag.withLock { stopped }
    }
}
