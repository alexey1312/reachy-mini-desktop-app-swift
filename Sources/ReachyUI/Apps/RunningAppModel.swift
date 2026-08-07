import Foundation
import Observation
import ReachyKit

/// Decides whether the global dock is on screen, keeps its reading fresh, and
/// carries the two actions it offers.
///
/// The *value* — which app holds the robot — lives on `RobotSession`, written by
/// the one funnel every app command already passes through. What lives here is
/// policy: how often to ask, when to stop asking, and which failures the user has
/// already waved away. That split is why the dock and the home-screen widget can
/// never disagree about what is running.
@MainActor
@Observable
final class RunningAppModel {
    typealias ConversationTurns = @MainActor (RobotSession, RobotApp) throws -> AsyncStream<ConversationTurn>

    /// Poll cadence. Injected so tests can assert the choice without sleeping it —
    /// a fixed `Task.sleep` before an assertion is a CI flake waiting to happen
    /// (project rule 7).
    struct Configuration: Sendable, Equatable {
        /// A transition the user is watching finish.
        var transitioning: Duration = .milliseconds(1500)
        /// Steady state: identity only changes when somebody acts, and every one of
        /// those actions already writes through `recordRunning`.
        var running: Duration = .seconds(10)
        /// Nothing to watch. Still worth asking, because an app can be started from
        /// the widget, the robot's own dashboard, or a wake-up autostart.
        var idle: Duration = .seconds(15)
    }

    /// How long a deep link asking for the running app's page waits for one to
    /// appear.
    ///
    /// It has to wait at all: the tap that sends it usually launches the app from
    /// cold, and there is no status to show until a connection and a poll have both
    /// come back. It has to stop waiting too — a sheet opening over whatever the
    /// user went on to do a minute later is not the page they asked for.
    static let expansionRequestWindow: TimeInterval = 30

    /// Which app-and-error the user dismissed. Keyed on both: the same app failing
    /// a *second*, different way is news again.
    private struct Dismissal: Equatable {
        let app: String
        let error: String?

        init(_ status: RobotAppStatus) {
            app = status.app.name
            error = status.error
        }
    }

    var isExpanded = false
    private(set) var busy = false
    private(set) var lastError: String?
    /// The app's own state inside the daemon's broader `.running` process state.
    /// Nil for every other app, old Conversation App builds, and remote sessions
    /// whose daemon cannot relay `/rpc` yet.
    private(set) var conversationTurn: ConversationTurn?

    private let configuration: Configuration
    private let conversationTurns: ConversationTurns
    private var dismissal: Dismissal?
    /// When a deep link last asked for the page, while there was nothing to open.
    private var requestedExpansion: Date?

    init(
        configuration: Configuration = Configuration(),
        conversationTurns: @escaping ConversationTurns = { try $0.conversationTurns(for: $1) }
    ) {
        self.configuration = configuration
        self.conversationTurns = conversationTurns
    }

    // MARK: - Visibility

    /// What the dock should render, or `nil` to stay out of the way.
    ///
    /// A pure function of the session, so the whole rule is testable without a
    /// robot, a timer or a view.
    func visibleStatus(for session: RobotSession) -> RobotAppStatus? {
        guard let status = session.runningApp else { return nil }
        switch session.phase {
        // `resetConnectionState()` clears `runningApp`, so this is belt and braces
        // rather than a reachable state — but a dock floating over the connection
        // screen is exactly the bug it would be.
        case .idle, .connecting: return nil
        case .connected, .unreachable: break
        }
        switch status.state {
        // A finished app is not news. An errored one is, until it has been read.
        case .done: return nil
        case .error where dismissal == Dismissal(status): return nil
        default: return status
        }
    }

    /// The robot stopped answering. The app is probably still running — but the
    /// controls cannot reach it, so they are shown inert rather than lying.
    func isReachable(_ session: RobotSession) -> Bool {
        if case .unreachable = session.phase {
            return false
        }
        return true
    }

    func dismissFailure(_ session: RobotSession) {
        guard let status = session.runningApp else { return }
        dismissal = Dismissal(status)
        isExpanded = false
    }

    /// A widget asking for the running app's page.
    ///
    /// Opened at once when there is something to open, held otherwise: the app is
    /// usually launching from cold, and a sheet cannot be presented over a status
    /// that has not arrived. `visibleStatusChanged` is what honours it when it does.
    func requestExpansion(for session: RobotSession, at date: Date = Date()) {
        // Dismissal suppresses an unsolicited repeat of a crash. A widget tap is
        // an explicit request to read it again, so let the same status back into
        // both the sheet binding and the sheet's content.
        if let status = session.runningApp, dismissal == Dismissal(status) {
            dismissal = nil
        }
        guard visibleStatus(for: session) == nil else {
            requestedExpansion = nil
            isExpanded = true
            return
        }
        requestedExpansion = date
    }

    func visibleStatusChanged(_ status: RobotAppStatus?, at date: Date = Date()) {
        guard status != nil else {
            isExpanded = false
            return
        }
        guard let requested = requestedExpansion else { return }
        requestedExpansion = nil
        guard date.timeIntervalSince(requested) <= Self.expansionRequestWindow else { return }
        isExpanded = true
    }

    // MARK: - Refresh

    /// One tick. `refreshCurrentApp()` writes the session through `recordRunning`, so
    /// nothing is assigned here — and a failed call leaves the last known app
    /// standing rather than blanking the dock, which is what a daemon mid-restart
    /// deserves.
    func refresh(session: RobotSession) async {
        guard canPoll(session) else { return }
        try? await session.refreshCurrentApp()
    }

    /// Polls until cancelled. There is no push channel for which app holds the
    /// robot — `/api/state/ws/full` carries nothing about apps — so this is the
    /// only way to notice one started from the widget or from the robot itself.
    func poll(session: RobotSession) async {
        while !Task.isCancelled {
            await refresh(session: session)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: interval(for: session.runningApp))
        }
    }

    /// The app capability appears as soon as a handshake installs its client. Wait
    /// until compatibility and readiness have accepted that client before using it.
    func canPoll(_ session: RobotSession) -> Bool {
        guard session.canManageApps else { return false }
        return switch session.phase {
        case .connected, .unreachable: true
        case .idle, .connecting: false
        }
    }

    /// A stable task identity for the one app whose own socket carries the official
    /// semantic conversation protocol. Returning nil tears the observer down while
    /// backgrounded, during process transitions, and over daemon 1.9's relay path
    /// (which has no address to dial).
    ///
    /// The port is part of the identity: a poll that refreshes the app's metadata
    /// can name a port where the last one only had the fallback, and the observer
    /// has to redial rather than sit on a socket to nowhere.
    func conversationStreamKey(
        for status: RobotAppStatus?,
        session: RobotSession,
        active: Bool
    ) -> String? {
        guard active,
              let status,
              status.state == .running,
              status.app.exposesConversationRPC,
              session.address != nil
        else { return nil }
        return "\(status.app.id)@\(status.app.customAppPort.map(String.init) ?? "default")"
    }

    /// Follows Conversation App 1.0's `conversation.turn` notifications. This is
    /// presentation enrichment only: an absent or old `/rpc` surface quietly
    /// leaves the daemon's ordinary "Running" caption in place.
    ///
    /// So does a live one until the conversation next moves. `turn` is push-only
    /// and emitted on change, and `conversation.status` answers with backend config
    /// rather than a state, so there is nothing to seed the first frame from.
    func observeConversation(status: RobotAppStatus?, session: RobotSession) async {
        conversationTurn = nil
        guard let status, status.state == .running, status.app.exposesConversationRPC,
              let turns = try? conversationTurns(session, status.app)
        else { return }

        for await turn in turns {
            guard !Task.isCancelled else { return }
            conversationTurn = turn
        }
    }

    /// Internal rather than private so a test can assert the cadence directly,
    /// instead of waiting one out.
    func interval(for status: RobotAppStatus?) -> Duration {
        guard let status else { return configuration.idle }
        return switch status.state {
        case .starting, .stopping: configuration.transitioning
        case .running, .unknown: configuration.running
        case .done, .error: configuration.idle
        }
    }

    // MARK: - Actions

    func stop(session: RobotSession) async {
        await run {
            try await session.stopCurrentApp()
            isExpanded = false
        }
    }

    func restart(session: RobotSession) async {
        await run { _ = try await session.restartCurrentApp() }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            lastError = nil
        } catch {
            lastError.recordDaemonFailure(error)
        }
    }
}

#if DEBUG
    extension RunningAppModel {
        /// Lives here rather than in `Previews/`: it writes `private(set)` members,
        /// which `@testable` does not reach from another module.
        static func preview(
            isExpanded: Bool = false,
            busy: Bool = false,
            error: String? = nil,
            conversationTurn: ConversationTurn? = nil
        ) -> RunningAppModel {
            let model = RunningAppModel()
            model.isExpanded = isExpanded
            model.busy = busy
            model.lastError = error
            model.conversationTurn = conversationTurn
            return model
        }
    }
#endif
