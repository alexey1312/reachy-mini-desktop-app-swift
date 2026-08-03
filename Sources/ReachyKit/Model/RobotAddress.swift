import Foundation

/// Network address of a robot daemon. Port is configurable (upstream hardcodes 8000).
public struct RobotAddress: Hashable, Sendable, Codable {
    public var host: String
    public var port: Int

    public static let defaultPort = 8000

    public init(host: String, port: Int = RobotAddress.defaultPort) {
        self.host = host
        self.port = port
    }

    /// Root URL of the daemon, e.g. `http://reachy-mini.local:8000`.
    /// Generated OpenAPI operation paths already include the `/api` prefix.
    public var rootURL: URL? {
        url(scheme: "http", path: "")
    }

    /// URL for a WebSocket endpoint, e.g. `ws://host:8000/api/state/ws/full`.
    public func webSocketURL(path: String) -> URL? {
        url(scheme: "ws", path: path)
    }

    /// Foundation's `URLComponents` rejects bare IPv6 literals in `host` — they must be
    /// pre-bracketed by the caller (upstream issue #269 was exactly this class of bug).
    private func url(scheme: String, path: String) -> URL? {
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components.port = port
        components.path = path
        return components.url
    }
}
