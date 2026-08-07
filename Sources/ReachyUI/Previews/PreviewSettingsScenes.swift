import HuggingFaceAuth
import ReachyKit
@testable import ReachyUI
import SwiftUI

/// The Settings tab's scenes, and the screens reached from it.
///
/// Split out of `PreviewScenes.swift` because that file sat exactly on SwiftLint's
/// 400-line limit and its enum body on the 300-line one, so the next scene added
/// anywhere in it failed the lint. `NavigationHost` and `View.preview()` are in
/// `PreviewHost.swift` rather than file-private here, which is what makes a second
/// file possible at all — see the note at the foot of `PreviewScenes.swift`.
@MainActor
extension PreviewScene {
    static func settings(_ session: RobotSession) -> some View {
        NavigationHost {
            SettingsScreen(session: session)
        }
        .preview()
    }

    static func yourReachies(
        _ state: YourReachiesModel.State,
        refreshFailure: String? = nil
    ) -> some View {
        NavigationHost {
            YourReachiesScreen(
                model: .preview(state, refreshFailure: refreshFailure),
                connect: { _ in },
                // The real destination: a pushed view costs nothing until it is
                // pushed, so the preview carries the one the app pushes rather
                // than a placeholder that would hide a broken link.
                signIn: { HFSignInScreen(session: .preview(), model: .preview()) }
            )
        }
        .preview()
    }

    /// The way in that «Your Reachies» pushes. Nothing is connected in this state —
    /// that is why the list was empty — so the plain preview client, which does not
    /// speak `HFAuthClient`, leaves the account half standing alone.
    static func hfSignIn(model: HFSignInModel? = nil) -> some View {
        NavigationHost {
            HFSignInScreen(session: .preview(), model: model ?? .preview())
        }
        .preview()
    }

    /// The account card on its own. The robot half only renders when the session's
    /// client speaks `HFAuthClient`, so the preview client is the one that does.
    static func hfAccount(
        model: HFSignInModel? = nil,
        robotAccount: HFAuthStatus? = nil,
        relay: RelayStatus? = nil,
        linkError: String? = nil
    ) -> some View {
        Form {
            HFAccountSection(
                session: .preview(
                    client: PreviewHFRobotClient(
                        account: robotAccount ?? HFAuthStatus(isLoggedIn: false),
                        relay: relay ?? RelayStatus(state: .stopped, isConnected: false)
                    )
                ),
                model: model ?? .preview(),
                robotAccount: robotAccount ?? HFAuthStatus(isLoggedIn: false),
                relay: relay ?? RelayStatus(state: .stopped, message: "Relay not initialized", isConnected: false),
                linkError: linkError
            )
        }
        .formStyle(.grouped)
        .preview()
    }

    static func updateCard(_ state: SystemUpdateModel.State, log: [String] = []) -> some View {
        Form {
            SystemUpdateCard(session: .preview(), model: .preview(state: state, log: log))
        }
        .formStyle(.grouped)
        .preview()
    }

    /// `runningApp` is the interesting axis: it is what blocks the uninstall, and
    /// it belongs to the session rather than to the model, so it is parked there.
    ///
    /// `nil` rather than `= .preview()`: a defaulted argument whose value is
    /// `@MainActor` compiles under SwiftPM and fails in the `Apps/` targets,
    /// where it is evaluated nonisolated. The card already builds its own.
    static func maintenanceCard(
        _ model: MaintenanceModel? = nil,
        runningApp: RobotAppStatus? = nil
    ) -> some View {
        Form {
            MaintenanceCard(session: .preview(runningApp: runningApp), model: model)
        }
        .formStyle(.grouped)
        .preview()
    }

    static func wifiCard(
        status: WiFiStatus? = nil,
        joinError: String? = nil,
        loadFailure: String? = nil
    ) -> some View {
        Form {
            WiFiSettingsCard(
                session: .preview(),
                status: status,
                joinError: joinError,
                loadFailure: loadFailure
            )
        }
        .formStyle(.grouped)
        .preview()
    }

    static func daemonUpdate(
        _ requirement: DaemonUpdateRequirement,
        state: SystemUpdateModel.State = .idle
    ) -> some View {
        NavigationHost {
            DaemonUpdateScreen(
                session: .preview(),
                requirement: requirement,
                model: .preview(state: state)
            )
        }
        .preview()
    }

    /// The console body on its own. It has three callers with three different sources, so it is
    /// worth snapshotting apart from any of them.
    static func consoleView(
        _ model: LogConsoleModel? = nil,
        source: String = "192.168.1.42",
        emptyDescription: String = "Daemon logs come from journalctl on the robot.",
        failure: String? = nil
    ) -> some View {
        NavigationHost {
            LogConsoleView(
                model: model ?? .preview(),
                source: source,
                emptyDescription: emptyDescription,
                failure: failure
            )
        }
        .preview()
    }
}
