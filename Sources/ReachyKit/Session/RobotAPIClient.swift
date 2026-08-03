import Foundation

/// The daemon surface `RobotSession` needs — abstracted so session logic is
/// testable without a network.
public protocol RobotAPIClient: Sendable {
    func handshake() async throws -> RobotConnection.Handshake
    func daemonStatus() async throws -> Components.Schemas.DaemonStatus
    func wakeUp() async throws -> String
    func gotoSleep() async throws -> String
    func setMotorMode(_ mode: Components.Schemas.MotorControlMode) async throws
    func startDaemon(wakeUp: Bool) async throws
    func listMoves(dataset: String) async throws -> [String]
    func playMove(dataset: String, move: String) async throws -> String
    func runningMoveUUIDs() async throws -> Set<String>
    func stopMove(uuid: String) async throws
    func stopSound() async throws
}

/// Defaults keep lightweight session test doubles focused on the behavior they exercise.
public extension RobotAPIClient {
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
}

extension RobotConnection: RobotAPIClient {}
