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

    private let configuration: Configuration
    private var dismissal: Dismissal?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
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

    // MARK: - Refresh

    /// One tick. `currentApp()` writes the session through `recordRunning`, so
    /// nothing is assigned here — and a failed call leaves the last known app
    /// standing rather than blanking the dock, which is what a daemon mid-restart
    /// deserves.
    func refresh(session: RobotSession) async {
        guard session.canManageApps else { return }
        _ = try? await session.currentApp()
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
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            error: String? = nil
        ) -> RunningAppModel {
            let model = RunningAppModel()
            model.isExpanded = isExpanded
            model.busy = busy
            model.lastError = error
            return model
        }
    }
#endif
