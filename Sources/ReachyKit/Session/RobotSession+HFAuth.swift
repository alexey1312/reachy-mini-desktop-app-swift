import Foundation

/// The robot's own Hugging Face account, reached through the session.
///
/// Two custody points, deliberately: this app keeps its token in the Keychain,
/// and the robot keeps its own copy. Linking is what puts the second one there —
/// over plain HTTP on the LAN, which is a limitation the UI has to state rather
/// than hide (ADR 0001).
public extension RobotSession {
    var canLinkHuggingFace: Bool {
        client is any HFAuthClient
    }

    /// Cached for the life of the connection: the daemon answers this by running
    /// `whoami` against the Hub every time, which is a network round trip to learn
    /// something that changes when the user says so.
    func robotHFAccount(refresh: Bool = false) async throws -> HFAuthStatus {
        if !refresh, let cached = hfAccountCache {
            return cached
        }
        let status = try await withHFAuthClient { try await $0.hfAuthStatus() }
        hfAccountCache = status
        return status
    }

    /// Hands the robot a token and asks the relay to pick it up at once, rather
    /// than on its next retry.
    ///
    /// The returned refresh says whether anything actually restarted — on
    /// `skipped` there is no state change coming, so a caller must not wait for
    /// one.
    @discardableResult
    func linkRobot(token: String) async throws -> RelayRefresh {
        let username = try await withHFAuthClient { try await $0.saveHFToken(token) }
        // `save-token` validated the token against the Hub to answer at all, so
        // the account is known — asking for the status again would repeat that
        // same `whoami`.
        hfAccountCache = HFAuthStatus(isLoggedIn: true, username: username)
        return try await withHFAuthClient { try await $0.refreshRelay() }
    }

    /// Removes the robot's token. This app's own sign-in is untouched — signing
    /// out here would leave the robot reachable from outside with a token the
    /// user thinks they revoked.
    func unlinkRobot() async throws {
        try await withHFAuthClient { try await $0.deleteHFToken() }
        hfAccountCache = nil
    }

    func relayStatus() async throws -> RelayStatus {
        try await withHFAuthClient { try await $0.relayStatus() }
    }

    /// Central's robot list, fetched by this robot with its own token so that no
    /// credential crosses the LAN.
    func centralRobotStatus() async throws -> CentralRobotStatusProxy {
        try await withHFAuthClient { try await $0.centralRobotStatus() }
    }
}

extension RobotSession {
    func withHFAuthClient<T>(_ call: (any HFAuthClient) async throws -> T) async throws -> T {
        guard let client else { throw ReachyKitError.notConnected }
        guard let authClient = client as? any HFAuthClient else {
            throw ReachyKitError.hfAuthUnavailable
        }
        do {
            let result = try await call(authClient)
            lastError = nil
            return result
        } catch {
            lastError = Self.describe(error)
            throw error
        }
    }
}
