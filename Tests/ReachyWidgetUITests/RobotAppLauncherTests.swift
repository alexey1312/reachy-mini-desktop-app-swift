import Foundation
import ReachyKit
@testable import ReachyWidgetUI
import Testing

/// One tap has to mean the whole sequence: find out what holds the robot, wake it
/// if it is parked, then start. Getting the order or the refusals wrong is how a
/// Home Screen button evicts somebody else's app or drops a head on a desk.
@Suite("Robot app launcher", .timeLimit(.minutes(1)))
struct RobotAppLauncherTests {
    private func launcher(_ client: StubAppsClient, assumeAwake: Bool? = true) -> RobotAppLauncher {
        RobotAppLauncher(client: client, assumeAwake: assumeAwake)
    }

    @Test("tapping the app that is running stops it")
    func stopsTheRunningApp() async throws {
        let client = StubAppsClient()
        client.running = StubAppsClient.status(name: "dance_party")

        let outcome = try await launcher(client).toggle(name: "dance_party")

        #expect(outcome == .stopped(name: "dance_party"))
        #expect(client.calls == [.currentAppStatus, .stopCurrentApp])
    }

    /// The daemon would evict it without asking, and `start-app/{app}/no-evict` is
    /// in the spec but not mounted on 1.9.0 — so refusing is the client's job.
    @Test("tapping another app while one is running refuses instead of evicting")
    func refusesWhileAnotherAppHoldsTheRobot() async throws {
        let client = StubAppsClient()
        client.running = StubAppsClient.status(name: "dance_party", title: "Dance Party")

        await #expect(throws: RobotAppLauncher.Failure.busy(title: "Dance Party")) {
            try await launcher(client).toggle(name: "face_tracking")
        }
        #expect(client.calls == [.currentAppStatus])
    }

    /// An app that finished is not an app holding the robot.
    @Test("a finished app does not block the next one")
    func startsOverAFinishedApp() async throws {
        let client = StubAppsClient()
        client.running = StubAppsClient.status(name: "dance_party", state: "done")

        let outcome = try await launcher(client).toggle(name: "face_tracking")

        #expect(outcome == .started(name: "face_tracking", title: "face tracking"))
    }

    @Test("nothing running means the app just starts")
    func startsWhenIdle() async throws {
        let client = StubAppsClient()

        let outcome = try await launcher(client).toggle(name: "face_tracking")

        #expect(outcome == .started(name: "face_tracking", title: "face tracking"))
        #expect(client.calls == [.currentAppStatus, .startApp("face_tracking")])
    }

    /// Motors first, then the animation, then the app — the order `RobotPower`
    /// exists to keep. Reversed, the head drops.
    @Test("a parked robot is woken before the app starts")
    func wakesAParkedRobot() async throws {
        let client = StubAppsClient()

        let outcome = try await launcher(client, assumeAwake: false).toggle(name: "face_tracking")

        #expect(outcome == .started(name: "face_tracking", title: "face tracking"))
        #expect(client.calls == [
            .currentAppStatus,
            .setMotorMode(.enabled),
            .wakeUp,
            .startApp("face_tracking"),
        ])
    }

    /// A fresh reading of the robot's state is worth a round trip saved: the whole
    /// budget here is a few seconds.
    @Test("a caller that already knows the robot is awake skips the check")
    func skipsTheReadinessCheckWhenTold() async throws {
        let client = StubAppsClient()

        _ = try await launcher(client, assumeAwake: true).toggle(name: "face_tracking")

        #expect(client.calls.contains(.daemonStatus) == false)
        #expect(client.calls.contains(.setMotorMode(.enabled)) == false)
    }

    @Test("a caller that does not know asks the daemon once")
    func asksTheDaemonWhenUnsure() async throws {
        let client = StubAppsClient()
        client.isAwake = false

        _ = try await launcher(client, assumeAwake: nil).toggle(name: "face_tracking")

        #expect(client.calls.filter { $0 == .daemonStatus }.count == 1)
        #expect(client.calls.contains(.wakeUp))
    }

    @Test("a name that would split the path is refused before anything is sent")
    func refusesANameWithASlash() async throws {
        let client = StubAppsClient()

        await #expect(throws: RobotAppLauncher.Failure.unusableName("owner/app")) {
            try await launcher(client).toggle(name: "owner/app")
        }
        #expect(client.calls.isEmpty)
    }

    /// Both budgets end in the same place — the app starts either way — and differ
    /// only in how long the wait takes, so the duration *is* the assertion
    /// (project rule 7). Ten seconds apart from four leaves room for a loaded
    /// runner.
    @Test("a wake animation that never finishes does not eat the intent's budget")
    func boundsTheWakeAnimation() async throws {
        let client = StubAppsClient()
        client.moveNeverFinishes = true

        let start = ContinuousClock.now
        _ = try await RobotAppLauncher(client: client, assumeAwake: false).toggle(name: "face_tracking")
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < .seconds(8))
        #expect(RobotSession.Configuration.widgetIntent.moveCompletionTimeout
            < RobotSession.Configuration().moveCompletionTimeout)
    }
}
