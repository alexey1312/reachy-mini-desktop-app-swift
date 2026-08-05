import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

@MainActor
@Suite("Running app dock", .timeLimit(.minutes(1)))
struct RunningAppModelTests {
    private static let app = RobotApp.previewInstalled[0]

    private func status(_ state: RobotAppStatus.State, error: String? = nil) -> RobotAppStatus {
        RobotAppStatus(app: Self.app, state: state, error: error)
    }

    private func session(
        _ state: RobotAppStatus.State?,
        error: String? = nil,
        phase: RobotSession.ConnectionPhase = .connected(.preview)
    ) -> RobotSession {
        .preview(phase: phase, runningApp: state.map { status($0, error: error) })
    }

    // MARK: - Visibility

    @Test("nothing running, nothing shown")
    func hiddenWithNoApp() {
        #expect(RunningAppModel().visibleStatus(for: session(nil)) == nil)
    }

    /// An app that ran to completion is not news. One that died is, because nobody
    /// asked it to.
    @Test("a finished app leaves, a crashed one stays")
    func distinguishesTerminalStates() {
        let model = RunningAppModel()

        #expect(model.visibleStatus(for: session(.done)) == nil)
        #expect(model.visibleStatus(for: session(.error, error: "boom"))?.state == .error)
    }

    @Test("every live state is shown", arguments: [
        RobotAppStatus.State.starting,
        .running,
        .stopping,
        .unknown("reloading"),
    ])
    func showsLiveStates(state: RobotAppStatus.State) {
        #expect(RunningAppModel().visibleStatus(for: session(state)) != nil)
    }

    /// `resetConnectionState()` clears the session's own reading, so this is belt
    /// and braces — but a dock floating over the connection screen is exactly the
    /// bug it guards.
    @Test("a disconnected session shows nothing, whatever it last knew")
    func hiddenWhileDisconnected() {
        let model = RunningAppModel()

        #expect(model.visibleStatus(for: session(.running, phase: .idle)) == nil)
        #expect(model.visibleStatus(for: session(.running, phase: .connecting(.handshaking))) == nil)
    }

    /// An unreachable robot keeps the dock: the app is probably still running, and
    /// removing the strip would read as "it stopped".
    @Test("an unreachable robot keeps the dock but disables its controls")
    func staysVisibleWhileUnreachable() {
        let model = RunningAppModel()
        let unreachable = session(.running, phase: .unreachable(.preview))

        #expect(model.visibleStatus(for: unreachable) != nil)
        #expect(model.isReachable(unreachable) == false)
        #expect(model.isReachable(session(.running)))
    }

    // MARK: - Dismissing a failure

    @Test("a dismissed failure stays dismissed")
    func dismissalSticks() {
        let model = RunningAppModel()
        let crashed = session(.error, error: "ImportError: no module named cv2")

        model.dismissFailure(crashed)

        #expect(model.visibleStatus(for: crashed) == nil)
    }

    /// Keyed on the failure, not just the app: the same app breaking a second,
    /// different way is news again.
    @Test("a different failure from the same app comes back")
    func dismissalIsKeyedOnTheError() {
        let model = RunningAppModel()
        model.dismissFailure(session(.error, error: "ImportError"))

        #expect(model.visibleStatus(for: session(.error, error: "OSError")) != nil)
    }

    @Test("dismissing also closes the expanded sheet")
    func dismissalCollapses() {
        let model = RunningAppModel()
        model.isExpanded = true

        model.dismissFailure(session(.error, error: "boom"))

        #expect(model.isExpanded == false)
    }

    // MARK: - Poll cadence

    /// Asserted as a value rather than waited out: a test that sleeps the interval
    /// to prove the interval is a flake on a loaded runner, and the wrong branch
    /// would pass it anyway — just later (project rule 7).
    @Test("a transition is watched closely, a steady state is not")
    func choosesItsCadence() {
        let model = RunningAppModel()
        let configuration = RunningAppModel.Configuration()

        #expect(model.interval(for: nil) == configuration.idle)
        #expect(model.interval(for: status(.starting)) == configuration.transitioning)
        #expect(model.interval(for: status(.stopping)) == configuration.transitioning)
        #expect(model.interval(for: status(.running)) == configuration.running)
        #expect(model.interval(for: status(.done)) == configuration.idle)
        #expect(model.interval(for: status(.error)) == configuration.idle)
        // Unfamiliar means "still holding the robot", so it is watched like one.
        #expect(model.interval(for: status(.unknown("reloading"))) == configuration.running)
    }

    @Test("the transition cadence is the tighter of the two")
    func transitionsArePolledFaster() {
        let configuration = RunningAppModel.Configuration()

        #expect(configuration.transitioning < configuration.running)
        #expect(configuration.running <= configuration.idle)
    }

    /// A relay session reaches the robot over a data channel that does not carry the
    /// apps protocol, so every tick would throw `.appsUnavailable`. Asking at all is
    /// the bug.
    @Test("a session with no app surface is never polled")
    func skipsRefreshWithoutTheCapability() async {
        let model = RunningAppModel()
        let session = RobotSession()
        #expect(session.canManageApps == false)

        await model.refresh(session: session)

        #expect(session.runningApp == nil)
        #expect(model.lastError == nil)
    }
}
