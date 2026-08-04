import Foundation

/// Speaker and microphone levels. The daemon has no separate notion of
/// microphone *sensitivity* — that is its input level, so both share `AudioLevel`.
public extension RobotSession {
    func volume() async throws -> AudioLevel {
        try await withClient { try await $0.volume() }
    }

    /// The daemon plays a test sound on every accepted call, so callers must send
    /// this once a slider gesture ends, not on every change.
    func setVolume(_ percent: Int) async throws -> AudioLevel {
        try await withClient { try await $0.setVolume(percent) }
    }

    func microphoneVolume() async throws -> AudioLevel {
        try await withClient { try await $0.microphoneVolume() }
    }

    func setMicrophoneVolume(_ percent: Int) async throws -> AudioLevel {
        try await withClient { try await $0.setMicrophoneVolume(percent) }
    }

    func playTestSound() async throws {
        try await withClient { try await $0.playTestSound() }
    }
}

public extension RobotSession {
    /// Renames the robot and folds the stored name back into the live identity, so
    /// the title bar does not keep showing the old one until the next connect.
    @discardableResult
    func rename(to name: String) async throws -> String {
        let stored = try await withClient { try await $0.setRobotName(name) }
        switch phase {
        case var .connected(identity):
            identity.name = stored
            phase = .connected(identity)
        case var .unreachable(identity):
            identity.name = stored
            phase = .unreachable(identity)
        default:
            break
        }
        return stored
    }
}

extension RobotSession {
    /// The guard-and-report shape every daemon call shares, factored out because
    /// audio alone would otherwise repeat it five times.
    func withClient<T>(_ call: (any RobotAPIClient) async throws -> T) async throws -> T {
        guard let client else { throw ReachyKitError.notConnected }
        do {
            try assertSupportedDaemon()
            let result = try await call(client)
            lastError = nil
            return result
        } catch {
            lastError = Self.describe(error)
            throw error
        }
    }
}
