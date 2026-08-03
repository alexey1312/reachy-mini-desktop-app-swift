import Foundation

/// The daemon surface `RobotSession` needs — abstracted so session logic is
/// testable without a network.
public protocol RobotAPIClient: Sendable {
    func handshake() async throws -> RobotConnection.Handshake
    func daemonStatus() async throws -> Components.Schemas.DaemonStatus
    func wakeUp() async throws
    func gotoSleep() async throws
}

extension RobotConnection: RobotAPIClient {}
