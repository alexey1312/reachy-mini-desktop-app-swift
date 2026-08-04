import Foundation
@testable import ReachyKit
import Testing

/// Daemon 1.9.0 does not mount `/api/daemon/robot-name` at all — it answers the bare
/// FastAPI 404 for both verbs. The handshake already reads that route for the display
/// name, so whether a robot can be renamed is known before the user is offered a field
/// that cannot save.
@Suite("RobotConnection rename support")
struct RobotConnectionRenameTests {
    private static let status = """
    {"type": "daemon_status", "robot_name": "reachy_mini", "state": "running",
     "wireless_version": true, "desktop_app_daemon": false,
     "backend_status": null, "version": "1.9.0", "hardware_id": "b68ff6bbe47f0608"}
    """

    private static let notFound = #"{"detail": "Not Found"}"#

    private func makeConnection(_ stubs: [String: StubURLProtocol.Stub]) throws -> RobotConnection {
        try RobotConnection(address: RobotAddress(host: "10.0.0.9"), session: StubURLProtocol.makeSession(stubs))
    }

    @Test("a daemon that serves the route can rename")
    func reportsSupportWhenRouteExists() async throws {
        let connection = try makeConnection([
            "/api/daemon/status": .init(statusCode: 200, json: Self.status),
            "/api/daemon/robot-name": .init(statusCode: 200, json: #"{"name": "testbot"}"#),
        ])

        let handshake = try await connection.handshake()

        #expect(handshake.supportsRename)
        #expect(handshake.identity.name == "testbot")
    }

    @Test("a 404 on the route means no rename, and the status name still stands")
    func reportsNoSupportWhenRouteMissing() async throws {
        let connection = try makeConnection([
            "/api/daemon/status": .init(statusCode: 200, json: Self.status),
            "/api/daemon/robot-name": .init(statusCode: 404, json: Self.notFound),
        ])

        let handshake = try await connection.handshake()

        #expect(!handshake.supportsRename)
        #expect(handshake.identity.name == "reachy_mini")
    }

    /// A transport failure is not evidence about the route: keep the feature offered
    /// and let the save report what actually went wrong.
    @Test("an unreadable route is not taken as proof the daemon cannot rename")
    func keepsSupportWhenTheRouteMerelyFails() async throws {
        let connection = try makeConnection([
            "/api/daemon/status": .init(statusCode: 200, json: Self.status),
            "/api/daemon/robot-name": .init(statusCode: 500),
        ])

        let handshake = try await connection.handshake()

        #expect(handshake.supportsRename)
    }

    @Test("renaming without the route reports the missing feature, not a bare 404")
    func mapsThe404ToTheFeature() async throws {
        let connection = try makeConnection([
            "/api/daemon/status": .init(statusCode: 200, json: Self.status),
            "/api/daemon/robot-name": .init(statusCode: 404, json: Self.notFound),
        ])

        await #expect(throws: ReachyKitError.renameUnavailable) {
            _ = try await connection.setRobotName("kitchen")
        }
    }
}
