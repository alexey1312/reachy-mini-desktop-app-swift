import Foundation
@testable import ReachyKit
import Testing

private final class RefreshAppsClient: RobotAPIClient, RobotAppsClient, @unchecked Sendable {
    private let base = PreviewRobotClient()
    private let lock = NSLock()
    private(set) var currentAppCalls = 0
    var failsCatalogue = false
    var failsCurrentApp = false

    func handshake() async throws -> RobotConnection.Handshake {
        try await base.handshake()
    }

    func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        try await base.daemonStatus()
    }

    func wakeUp() async throws -> String {
        try await base.wakeUp()
    }

    func gotoSleep() async throws -> String {
        try await base.gotoSleep()
    }

    func availableApps() async throws -> [RobotApp] {
        if failsCatalogue {
            throw ReachyKitError.daemonRejected(statusCode: 503)
        }
        return []
    }

    func currentAppStatus() async throws -> RobotAppStatus? {
        try lock.withLock {
            currentAppCalls += 1
            if failsCurrentApp {
                throw ReachyKitError.daemonRejected(statusCode: 503)
            }
            return nil
        }
    }
}

@MainActor
@Suite("Robot session background app refresh", .timeLimit(.minutes(1)))
struct RobotSessionAppRefreshTests {
    /// The dock polls on a timer behind whatever the user is looking at. Neither
    /// its successes nor its failures may disturb `robotError`, which by now only
    /// the connection and power paths write — a background poll that could clear a
    /// wake failure would take the message away mid-read.
    @Test("a background app refresh leaves the session error channel alone")
    func preservesErrors() async throws {
        let client = RefreshAppsClient()
        let defaults = try #require(UserDefaults(
            suiteName: "RobotSessionAppRefreshTests.\(UUID().uuidString)"
        ))
        let session = RobotSession(
            snapshots: RobotSnapshotStore(defaults: defaults),
            appsCache: RobotAppsCacheStore(defaults: defaults)
        ) { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))

        let standing = "Robot backend did not start within 90 seconds."
        session.robotError = standing

        client.failsCatalogue = true
        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 503)) {
            _ = try await session.appCatalogue(refresh: true)
        }
        #expect(session.robotError == standing)

        client.failsCatalogue = false
        try await session.refreshCurrentApp()
        #expect(session.robotError == standing)

        client.failsCurrentApp = true
        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 503)) {
            try await session.refreshCurrentApp()
        }
        #expect(session.robotError == standing)
    }

    @Test("a background app refresh cannot cross the compatibility gate")
    func waitsForConnection() async {
        let client = RefreshAppsClient()
        let requirement = DaemonUpdateRequirement(
            reported: "1.8.0",
            minimum: "1.9.0",
            canSelfUpdate: true
        )
        let session = RobotSession.preview(
            phase: .connecting(.needsDaemonUpdate(.preview, requirement)),
            client: client
        )

        await #expect(throws: ReachyKitError.notConnected) {
            try await session.refreshCurrentApp()
        }
        #expect(client.currentAppCalls == 0)
    }
}
