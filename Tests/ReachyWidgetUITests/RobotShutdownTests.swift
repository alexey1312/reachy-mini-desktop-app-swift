import Foundation
import ReachyKit
@testable import ReachyWidgetUI
import Testing

/// Powering off has one ordering rule and one thing it refuses to abort on, and
/// both exist because of what the daemon does *not* do: its teardown never touches
/// the app manager, so a running app is left executing against a backend that has
/// gone.
@Suite("Robot shutdown", .timeLimit(.minutes(1)))
struct RobotShutdownTests {
    private func shutdown(_ client: StubAppsClient) -> RobotShutdown {
        RobotShutdown(apps: client, daemon: client)
    }

    @Test("the running app is stopped before the backend goes")
    func stopsTheAppFirst() async throws {
        let client = StubAppsClient()
        client.running = StubAppsClient.status(name: "dance_party")

        try await shutdown(client).perform()

        #expect(client.calls == [.currentAppStatus, .stopCurrentApp, .stopDaemon(gotoSleep: true)])
    }

    /// The parking is the daemon's: `stop?goto_sleep=true` enables the motors,
    /// awaits the animation and only then cuts power, which is more than
    /// `RobotPower.sleep()` does. A client-side sleep first would only delay it.
    @Test("nothing is played client-side on the way down")
    func leavesTheSleepToTheDaemon() async throws {
        let client = StubAppsClient()

        try await shutdown(client).perform()

        #expect(client.calls == [.currentAppStatus, .stopDaemon(gotoSleep: true)])
    }

    @Test("an app that already finished is not stopped again")
    func ignoresAFinishedApp() async throws {
        let client = StubAppsClient()
        client.running = StubAppsClient.status(name: "dance_party", state: "done")

        try await shutdown(client).perform()

        #expect(client.calls.contains(.stopCurrentApp) == false)
    }

    /// The robot's body is parked either way, and that is the half that matters.
    /// `RobotSession.powerOff` reports this failure because it has a screen; an
    /// intent has one sentence and it belongs to the shutdown.
    @Test("failing to stop the app does not abort the shutdown")
    func shutsDownAnywayWhenTheAppWillNotStop() async throws {
        let client = StubAppsClient()
        client.running = StubAppsClient.status(name: "dance_party")
        client.stopAppFails = true

        try await shutdown(client).perform()

        #expect(client.calls.contains(.stopDaemon(gotoSleep: true)))
    }

    @Test("a daemon that refuses the shutdown is reported")
    func reportsARefusedShutdown() async throws {
        let client = StubAppsClient()
        client.stopDaemonFails = true

        await #expect(throws: StubAppsClient.Refused.self) {
            try await shutdown(client).perform()
        }
    }
}
