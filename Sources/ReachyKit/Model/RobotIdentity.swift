import Foundation

/// Stable identity of a robot, established during the connection handshake.
///
/// Robots are identified by hardware ID, never by network address — one robot can
/// be reachable at several addresses at once (upstream issue #269).
public struct RobotIdentity: Hashable, Sendable, Codable {
    /// From `GET /api/daemon/hardware-id`.
    public var hardwareID: String
    /// From `GET /api/daemon/robot-name`.
    public var name: String?
    /// Daemon version reported on handshake; drives graceful degradation for unknown fields.
    public var daemonVersion: String?

    public init(hardwareID: String, name: String? = nil, daemonVersion: String? = nil) {
        self.hardwareID = hardwareID
        self.name = name
        self.daemonVersion = daemonVersion
    }
}
