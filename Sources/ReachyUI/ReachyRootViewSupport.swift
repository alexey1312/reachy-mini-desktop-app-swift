import ReachyKit
import SwiftUI
import WidgetKit

/// The subset of the session a widget actually renders, so `onChange` fires when
/// that changes and not on every unrelated field of the daemon's status.
struct RobotWidgetFacts: Equatable {
    let phase: RobotSession.ConnectionPhase
    let isAwake: Bool
    /// The whole status rather than its name: the widget dims every tile but one
    /// while an app holds the robot, marks the one that died, and prints the
    /// daemon's own sentence under the grid — so the state and the error are as
    /// much a reason to rebuild a timeline as the name is.
    ///
    /// Read from the session, not back out of the snapshot store. `UserDefaults` is
    /// not observable, so that reading only ever changed under a body being
    /// re-evaluated for some other reason; this one is what `RobotSession+Apps`
    /// assigns in the same funnel that writes the snapshot, and observing it is
    /// what makes the reload follow the fact rather than accompany it.
    let runningApp: RobotAppStatus?
}

/// The link owns signaling, the peer connection and potentially an open
/// microphone. Recoverable states keep it; leaving remote mode and terminal
/// connection failures end it.
enum RemoteLinkLifetime {
    static func shouldKeepAlive(
        isRemote: Bool,
        phase: RobotSession.ConnectionPhase
    ) -> Bool {
        guard isRemote else { return false }
        return switch phase {
        case .connected, .unreachable:
            true
        case let .connecting(step):
            switch step {
            case .handshaking, .checkingBackend, .backendUnavailable:
                true
            case .needsDaemonUpdate, .failed:
                false
            }
        case .idle:
            false
        }
    }
}

extension View {
    /// Tells the widget extension the reading it holds has moved on.
    ///
    /// Lives beside `RobotWidgetFacts` rather than in the root view: it is entirely
    /// about the widget, and the root view is at its length limit.
    func widgetReload(session: RobotSession, isPreview: Bool) -> some View {
        onChange(
            of: RobotWidgetFacts(
                phase: session.phase,
                isAwake: session.isAwake,
                runningApp: session.runningApp
            )
        ) { _, _ in
            guard !isPreview else { return }
            // The widget cannot ask the robot anything. `RobotSession` has already
            // written the snapshot by this point.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
