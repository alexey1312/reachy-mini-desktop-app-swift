import Foundation
@testable import ReachyKit
import ReachyTestSupport
import Testing

/// `.ok` on a generated call turns every non-200 into an opaque `undocumented`
/// runtime error. These pin the explicit mappings that make the readiness gate
/// and the error banner say something actionable.
@Suite("RobotConnection status mapping")
struct RobotConnectionStatusMappingTests {
    private func makeConnection(_ stubs: [String: StubURLProtocol.Stub]) throws -> RobotConnection {
        try RobotConnection(address: RobotAddress(host: "10.0.0.9"), session: StubURLProtocol.makeSession(stubs))
    }

    @Test("503 on the readiness probe is the backend-not-running signal")
    func readinessProbeMaps503() async throws {
        let connection = try makeConnection([
            "/api/state/full": .init(statusCode: 503, json: #"{"detail": "Backend not running"}"#),
        ])

        await #expect(throws: ReachyKitError.backendNotRunning) {
            try await connection.probeBackendReady()
        }
    }

    @Test("an unexpected daemon status code keeps its number")
    func daemonStatusMaps500() async throws {
        let connection = try makeConnection(["/api/daemon/status": .init(statusCode: 500)])

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 500)) {
            _ = try await connection.daemonStatus()
        }
    }
}
