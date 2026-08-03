import Foundation

/// Stable identity of a robot, established during the connection handshake.
///
/// Robots are identified by hardware ID, never by network address — one robot can
/// be reachable at several addresses at once (upstream issue #269).
public struct RobotIdentity: Hashable, Sendable, Codable {
    /// From `GET /api/daemon/hardware-id`. `nil` when the daemon reports none
    /// (simulation) — fall back to `name` for deduplication then.
    public var hardwareID: String?
    /// From `GET /api/daemon/robot-name`.
    public var name: String?
    /// Daemon version reported on handshake; drives graceful degradation for unknown fields.
    public var daemonVersion: String?

    public init(hardwareID: String? = nil, name: String? = nil, daemonVersion: String? = nil) {
        self.hardwareID = hardwareID
        self.name = name
        self.daemonVersion = daemonVersion
    }

    /// Stable key for deduplicating discovery results (issue #269 class of bugs).
    public var deduplicationKey: String {
        hardwareID ?? name ?? "unknown"
    }
}
