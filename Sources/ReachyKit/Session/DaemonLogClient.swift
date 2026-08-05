import Foundation

/// A connection that can tail the robot's journal.
///
/// Both transports can, by genuinely different means — a WebSocket to
/// `/logs/ws/daemon` over the LAN, a `subscribe_logs` subscription over the data
/// channel — so the console reads lines without knowing which one it is on. The
/// daemon deliberately does not classify severity on either path: it sends the
/// text and clients parse it, which is why this carries plain strings.
public protocol DaemonLogClient: Sendable {
    /// Journal lines, one per element, in the daemon's own `short-iso` shape.
    /// Never throws mid-stream; ends on cancellation or when the source gives up.
    func daemonLogLines() throws -> AsyncStream<String>
}

extension RobotConnection: DaemonLogClient {
    /// The route is mounted at the app root and only under `--wireless-version`,
    /// so the simulator refuses the upgrade with a 403 — which the console shows
    /// as an empty stream rather than hiding.
    public nonisolated func daemonLogLines() throws -> AsyncStream<String> {
        try LogStreamClient(address: address).lines()
    }
}

extension RemoteRobotConnection: DaemonLogClient {
    public nonisolated func daemonLogLines() throws -> AsyncStream<String> {
        RemoteDaemonLog(control: control).lines()
    }
}

public extension RobotSession {
    var canReadDaemonLogs: Bool {
        client is any DaemonLogClient
    }

    func daemonLogLines() throws -> AsyncStream<String> {
        guard let client else { throw ReachyKitError.notConnected }
        guard let logs = client as? any DaemonLogClient else {
            throw ReachyKitError.daemonLogsUnavailable
        }
        return try logs.daemonLogLines()
    }
}
