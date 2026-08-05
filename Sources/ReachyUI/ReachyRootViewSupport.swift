import ReachyKit
import SwiftUI
import WidgetKit

/// The subset of the session a widget actually renders, so `onChange` fires when
/// that changes and not on every unrelated field of the daemon's status.
struct RobotWidgetFacts: Equatable {
    let phase: RobotSession.ConnectionPhase
    let isAwake: Bool
    /// The launcher dims every tile but one while an app holds the robot, so
    /// starting one from the Apps screen has to reach the widget too. Read back
    /// out of the snapshot rather than from the session: `RobotSession+Apps` is
    /// what learns it, and only on the calls that already ask.
    let runningApp: String?
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
                runningApp: RobotSnapshotStore().current?.runningAppName
            )
        ) { _, _ in
            guard !isPreview else { return }
            // The widget cannot ask the robot anything. `RobotSession` has already
            // written the snapshot by this point.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// A large title inside a narrow side column is laid out against the window
    /// rather than the column, so it starts flush against the divider with no
    /// leading inset. Inline titles sit correctly.
    func columnTitleStyle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }
}
