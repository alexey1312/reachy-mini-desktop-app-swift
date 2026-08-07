import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

private struct AppsCapablePreviewClient: RobotAPIClient, RobotAppsClient {
    private let base = PreviewRobotClient()

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
}

@MainActor
@Suite("Running app dock", .timeLimit(.minutes(1)))
struct RunningAppModelTests {
    private static let app = RobotApp.previewInstalled[0]
    private static let conversationApp = RobotApp.previewConversation

    private func status(_ state: RobotAppStatus.State, error: String? = nil) -> RobotAppStatus {
        RobotAppStatus(app: Self.app, state: state, error: error)
    }

    private func session(
        _ state: RobotAppStatus.State?,
        error: String? = nil,
        phase: RobotSession.ConnectionPhase = .connected(.preview),
        client: any RobotAPIClient = PreviewRobotClient()
    ) -> RobotSession {
        .preview(phase: phase, runningApp: state.map { status($0, error: error) }, client: client)
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

    @Test("the expanded sheet closes when its app disappears")
    func disappearanceCollapses() {
        let model = RunningAppModel()
        model.isExpanded = true

        model.visibleStatusChanged(status(.running))
        #expect(model.isExpanded)

        model.visibleStatusChanged(nil)
        #expect(!model.isExpanded)
    }

    // MARK: - A deep link asking for the page

    @Test("a link that arrives with an app running opens it at once")
    func expandsImmediately() {
        let model = RunningAppModel()

        model.requestExpansion(for: session(.running))

        #expect(model.isExpanded)
    }

    /// The widget tap that sends this usually launches the app from cold, so there
    /// is nothing to present until a connection and a poll have both come back.
    @Test("a link that arrives before the status does waits for it")
    func expandsOnceTheStatusArrives() {
        let model = RunningAppModel()

        model.requestExpansion(for: session(nil))
        #expect(model.isExpanded == false)

        model.visibleStatusChanged(status(.running))
        #expect(model.isExpanded)
    }

    /// Past the window the user has gone on to something else, and a sheet opening
    /// over it is not the page they asked for.
    @Test("a link that waited too long is dropped rather than honoured late")
    func dropsAStaleRequest() {
        let model = RunningAppModel()
        let asked = Date(timeIntervalSince1970: 1_800_000_000)

        model.requestExpansion(for: session(nil), at: asked)
        model.visibleStatusChanged(
            status(.running),
            at: asked.addingTimeInterval(RunningAppModel.expansionRequestWindow + 1)
        )

        #expect(model.isExpanded == false)
    }

    /// One request, one sheet. An app restarting a minute later must not reopen it.
    @Test("a honoured request is not honoured twice")
    func honoursARequestOnce() {
        let model = RunningAppModel()

        model.requestExpansion(for: session(nil))
        model.visibleStatusChanged(status(.running))
        model.isExpanded = false
        model.visibleStatusChanged(status(.running))

        #expect(model.isExpanded == false)
    }

    /// A crash is the case the link exists for: the tile says "Failed" and the page
    /// is the only place the traceback is.
    @Test("a crashed app is something to open")
    func expandsOnACrash() {
        let model = RunningAppModel()

        model.requestExpansion(for: session(.error, error: "ImportError"))

        #expect(model.isExpanded)
    }

    /// Dismissal stops the crash from reopening on its own. Tapping the widget is
    /// a new, explicit request to read that same traceback again.
    @Test("a link reopens a dismissed crash")
    func reopensADismissedCrash() {
        let model = RunningAppModel()
        let crashed = session(.error, error: "ImportError")
        model.dismissFailure(crashed)
        #expect(model.visibleStatus(for: crashed) == nil)

        model.requestExpansion(for: crashed)

        #expect(model.visibleStatus(for: crashed)?.state == .error)
        #expect(model.isExpanded)
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

    @Test("polling starts only after compatibility and readiness accept the client")
    func pollsOnlyEstablishedSessions() {
        let model = RunningAppModel()
        let client = AppsCapablePreviewClient()
        let requirement = DaemonUpdateRequirement(
            reported: "1.8.0",
            minimum: "1.9.0",
            canSelfUpdate: true
        )

        #expect(!model.canPoll(session(nil, phase: .idle, client: client)))
        #expect(!model.canPoll(session(nil, phase: .connecting(.handshaking), client: client)))
        #expect(!model.canPoll(session(
            nil,
            phase: .connecting(.needsDaemonUpdate(.preview, requirement)),
            client: client
        )))
        #expect(model.canPoll(session(nil, phase: .connected(.preview), client: client)))
        #expect(model.canPoll(session(nil, phase: .unreachable(.preview), client: client)))
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

    // MARK: - Conversation turn

    @Test("only a running official conversation app gets a turn stream")
    func choosesConversationStream() {
        let model = RunningAppModel()
        let connected = session(.running)
        let conversation = RobotAppStatus(app: Self.conversationApp, state: .running)

        #expect(model.conversationStreamKey(for: conversation, session: connected, active: true) != nil)
        #expect(model.conversationStreamKey(for: status(.running), session: connected, active: true) == nil)
        #expect(model.conversationStreamKey(
            for: RobotAppStatus(app: Self.conversationApp, state: .starting),
            session: connected,
            active: true
        ) == nil)
        #expect(model.conversationStreamKey(for: conversation, session: connected, active: false) == nil)
        #expect(model.conversationStreamKey(
            for: conversation,
            session: .preview(link: .remote),
            active: true
        ) == nil)
    }

    /// `.task(id:)` restarts on a changed id and on nothing else, so a port the
    /// daemon only learned on the second poll has to change the key.
    @Test("a newly reported port redials rather than reusing the socket")
    func portIsPartOfTheStreamIdentity() {
        let model = RunningAppModel()
        let connected = session(.running)
        let unknownPort = RobotAppStatus(
            app: .preview(name: "reachy_mini_conversation_app", installed: true),
            state: .running
        )
        let key = { (status: RobotAppStatus) in
            model.conversationStreamKey(for: status, session: connected, active: true)
        }

        #expect(key(RobotAppStatus(app: Self.conversationApp, state: .running)) != key(unknownPort))
        #expect(key(unknownPort) != nil)
    }

    @Test("the latest semantic turn enriches the process status")
    func observesConversationTurn() async {
        let turns = AsyncStream<ConversationTurn> { continuation in
            continuation.yield(.thinking)
            continuation.yield(.speaking)
            continuation.finish()
        }
        let model = RunningAppModel(conversationTurns: { _, _ in turns })
        let conversation = RobotAppStatus(app: Self.conversationApp, state: .running)

        await model.observeConversation(status: conversation, session: session(.running))

        #expect(model.conversationTurn == .speaking)
    }

    /// The seam is handed the app, not just the session: the port lives on the app
    /// and dialling the daemon's own 8000 would reach the REST API instead.
    @Test("the observed app is the one the stream is opened for")
    func opensTheStreamForTheRunningApp() async {
        final class Observed { var app: RobotApp? }
        let observed = Observed()
        let model = RunningAppModel(conversationTurns: { _, app in
            observed.app = app
            return AsyncStream { $0.finish() }
        })

        await model.observeConversation(
            status: RobotAppStatus(app: Self.conversationApp, state: .running),
            session: session(.running)
        )

        #expect(observed.app?.customAppPort == 7860)
    }

    @Test("an unavailable RPC surface quietly keeps the ordinary status")
    func ignoresUnavailableConversationSurface() async {
        struct Unavailable: Error {}
        let model = RunningAppModel(conversationTurns: { _, _ in throw Unavailable() })
        let conversation = RobotAppStatus(app: Self.conversationApp, state: .running)

        await model.observeConversation(status: conversation, session: session(.running))

        #expect(model.conversationTurn == nil)
    }
}
