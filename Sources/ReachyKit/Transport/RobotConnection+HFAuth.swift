import Foundation

/// `/api/hf-auth/*`.
///
/// The two token routes go through the generated client, which is what puts the
/// token in a JSON body rather than anywhere it could be logged. The other four
/// are declared `additionalProperties: true` in the spec, so the generated client
/// hands back an untyped container — decoding the raw payload directly costs less
/// than re-encoding that container, and lets every enum stay tolerant of a value
/// a later daemon invents (project rule 3).
extension RobotConnection: HFAuthClient {
    public func hfAuthStatus() async throws -> HFAuthStatus {
        try await hubJSON(path: "/api/hf-auth/status")
    }

    /// 400 when the Hub refuses the token — the daemon runs `whoami` before it
    /// stores anything.
    @discardableResult
    public func saveHFToken(_ token: String) async throws -> String? {
        switch try await hubClient.saveTokenApiHfAuthSaveTokenPost(body: .json(.init(token: token))) {
        case let .ok(response):
            return try response.body.json.username
        case .unprocessableContent:
            throw ReachyKitError.daemonRejected(statusCode: 422)
        case let .undocumented(statusCode, _):
            throw ReachyKitError.fromStatusCode(statusCode)
        }
    }

    public func deleteHFToken() async throws {
        switch try await hubClient.deleteTokenApiHfAuthTokenDelete() {
        case .ok:
            return
        case let .undocumented(statusCode, _):
            throw ReachyKitError.fromStatusCode(statusCode)
        }
    }

    public func relayStatus() async throws -> RelayStatus {
        try await hubJSON(path: "/api/hf-auth/relay-status")
    }

    @discardableResult
    public func refreshRelay() async throws -> RelayRefresh {
        try await hubJSON(method: "POST", path: "/api/hf-auth/refresh-relay")
    }

    public func centralRobotStatus() async throws -> CentralRobotStatusProxy {
        try await hubJSON(path: "/api/hf-auth/central-robot-status")
    }
}
