import Foundation

/// The daemon surface `RobotSession` needs — abstracted so session logic is
/// testable without a network.
public protocol RobotAPIClient: Sendable {
    func handshake() async throws -> RobotConnection.Handshake
    func daemonStatus() async throws -> Components.Schemas.DaemonStatus
    func probeBackendReady() async throws
    func wakeUp() async throws -> String
    func gotoSleep() async throws -> String
    func setMotorMode(_ mode: Components.Schemas.MotorControlMode) async throws
    func startDaemon(wakeUp: Bool) async throws
    func listMoves(dataset: String) async throws -> [String]
    func playMove(dataset: String, move: String) async throws -> String
    func runningMoveUUIDs() async throws -> Set<String>
    func stopMove(uuid: String) async throws
    func stopSound() async throws
    func urdf() async throws -> String
    func stlAsset(named filename: String) async throws -> Data
    func kinematicsInfo() async throws -> KinematicsInfo
}

/// Defaults keep lightweight session test doubles focused on the behavior they exercise.
public extension RobotAPIClient {
    /// Succeeds rather than throwing like its neighbours: a throwing default would
    /// route every double that doesn't script readiness into `.backendUnavailable`,
    /// turning an unimplemented method into a connection failure.
    func probeBackendReady() async throws {}

    func setMotorMode(_: Components.Schemas.MotorControlMode) async throws {
        throw URLError(.unsupportedURL)
    }

    func startDaemon(wakeUp _: Bool) async throws {
        throw URLError(.unsupportedURL)
    }

    func listMoves(dataset _: String) async throws -> [String] {
        throw URLError(.unsupportedURL)
    }

    func playMove(dataset _: String, move _: String) async throws -> String {
        throw URLError(.unsupportedURL)
    }

    func runningMoveUUIDs() async throws -> Set<String> {
        throw URLError(.unsupportedURL)
    }

    func stopMove(uuid _: String) async throws {
        throw URLError(.unsupportedURL)
    }

    func stopSound() async throws {
        throw URLError(.unsupportedURL)
    }

    func urdf() async throws -> String {
        throw URLError(.unsupportedURL)
    }

    func stlAsset(named _: String) async throws -> Data {
        throw URLError(.unsupportedURL)
    }

    func kinematicsInfo() async throws -> KinematicsInfo {
        throw URLError(.unsupportedURL)
    }
}

extension RobotConnection: RobotAPIClient {}
