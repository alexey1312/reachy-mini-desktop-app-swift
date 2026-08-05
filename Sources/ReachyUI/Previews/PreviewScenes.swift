import HuggingFaceAuth
import ReachyKit
@testable import ReachyUI
import SwiftUI

/// Wrappers shared by preview bodies.
///
/// Deliberately not `private`, and deliberately not free functions: Prefire copies each preview's
/// body verbatim into a generated test file, so anything a body references has to be visible
/// across the whole target. A `private` helper compiles fine in the preview file and then fails
/// the generated test with "cannot find … in scope".
///
/// Every wrapper sets `reachyPreviewMode`, so no individual preview can forget it and leave a
/// WebSocket reconnecting in the background while the snapshot is taken.
@MainActor
enum PreviewScene {
    static let address = RobotAddress(host: "192.168.1.42")

    static func robotScreen(_ session: RobotSession) -> some View {
        NavigationHost {
            RobotScreen(session: session)
        }
        .preview()
    }

    static func stepper(
        _ step: RobotSession.ConnectionStep,
        powerTransition: RobotSession.PowerTransition? = nil
    ) -> some View {
        Form {
            ConnectionStepper(session: .preview(phase: .connecting(step), powerTransition: powerTransition))
        }
        .formStyle(.grouped)
        .preview()
    }

    /// The model defaults are `nil` rather than `.preview()`: a default argument is evaluated in a
    /// nonisolated context, and every one of these factories is main-actor isolated.
    static func movesScreen(_ session: RobotSession, model: MovesModel? = nil) -> some View {
        NavigationHost {
            MovesScreen(session: session, model: model ?? .preview())
        }
        .preview()
    }

    static func appStore(
        _ session: RobotSession,
        model: AppStoreModel? = nil,
        install: AppInstallModel? = nil
    ) -> some View {
        NavigationHost {
            AppStoreScreen(
                session: session,
                model: model ?? .preview(),
                install: install ?? .preview(state: .idle, session: session)
            )
        }
        .preview()
    }

    /// The sheet the store opens, previewed on its own: it carries the whole
    /// install flow, and a snapshot of it is the only view of a job in flight.
    static func appDetail(
        _ session: RobotSession,
        app: RobotApp,
        model: AppStoreModel? = nil,
        install: AppInstallModel? = nil
    ) -> some View {
        NavigationHost {
            AppDetailSheet(
                app: app,
                model: model ?? .preview(),
                session: session,
                install: install ?? .preview(state: .idle, session: session),
                dismiss: {}
            )
        }
        .preview()
    }

    static func logConsole(_ model: LogConsoleModel? = nil, setupError: String? = nil) -> some View {
        NavigationHost {
            LogConsoleScreen(address: address, model: model ?? .preview(), setupError: setupError)
        }
        .preview()
    }

    static func audioSection(_ model: AudioSettingsModel? = nil, header: String? = "Audio") -> some View {
        Form {
            AudioSettingsSection(session: .preview(), header: header, model: model ?? .preview())
        }
        .formStyle(.grouped)
        .preview()
    }

    static func controller(
        _ session: RobotSession,
        target: SetTargetClient.Target = SetTargetClient.Target(),
        setupError: String? = nil
    ) -> some View {
        NavigationHost {
            ControllerScreen(session: session, address: address, target: target, setupError: setupError)
        }
        .preview()
    }

    static func viewport(_ model: ViewportModel, offersCamera: Bool = true) -> some View {
        ViewportView(model: model, offersCamera: offersCamera)
            .preview()
    }

    /// The viewport fills whatever it is given, so previews of its inner panes need a frame or
    /// they collapse to nothing on a `sizeThatFits` capture.
    static func pane(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .preview()
    }

    static func connection(
        _ session: RobotSession,
        browser: RobotBrowser? = nil,
        manualInput: String = "",
        knownRobots: KnownRobotsModel? = nil
    ) -> some View {
        ConnectionScreen(
            session: session,
            browser: browser ?? .preview(names: []),
            manualInput: manualInput,
            knownRobots: knownRobots ?? .preview([])
        )
        .preview()
    }

    static func root(_ session: RobotSession, viewport: ViewportModel? = nil) -> some View {
        ReachyRootView(session: session, viewport: viewport ?? .preview()) {
            Text("Developer tools")
        }
        .preview()
    }

    /// A journal short enough to fit a card, with one line per level the console colours.
    static let journalLines = [
        "2026-08-04T09:12:01 INFO reachy_mini.daemon: starting backend",
        "2026-08-04T09:12:02 WARNING NetworkManager: wlan0 disconnected",
        "2026-08-04T09:12:04 ERROR reachy_mini.daemon: no route to host",
    ]

    /// pip is what the robot's updater actually shells out to.
    static let installerLines = [
        "Collecting reachy-mini==1.9.1",
        "  Downloading reachy_mini-1.9.1-py3-none-any.whl (2.1 MB)",
        "Installing collected packages: reachy-mini",
        "Successfully installed reachy-mini-1.9.1",
    ]

    // MARK: - Provisioning over Bluetooth

    /// Every onboarding step goes through the flow rather than being rendered on its own, so the
    /// snapshot carries the stack and the Cancel button the user actually sees.
    static func onboarding(_ model: OnboardingModel) -> some View {
        OnboardingFlow(model: model, onFinish: { _ in }, onCancel: {})
            .preview()
    }

    static func bleConsole(_ model: BLEConsoleModel) -> some View {
        NavigationHost {
            BLEConsoleScreen(model: model)
        }
        .preview()
    }

    static func commands(_ model: BLEConsoleModel) -> some View {
        NavigationHost {
            BLERecoveryCommandsSheet(model: model)
        }
        .preview()
    }

    static func softwareReset(
        _ model: BLEConsoleModel,
        acknowledged: Bool = false,
        typedID: String = "",
        code: String = "",
        dispatched: Bool = false,
        stillAnswering: Bool? = nil
    ) -> some View {
        NavigationHost {
            BLESoftwareResetScreen(
                model: model,
                script: .describing("SOFTWARE_RESET"),
                acknowledged: acknowledged,
                typedID: typedID,
                code: code,
                dispatched: dispatched,
                stillAnswering: stillAnswering
            )
        }
        .preview()
    }

    // MARK: - Settings and updates

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

private extension View {
    func preview() -> some View {
        environment(\.reachyPreviewMode, true)
    }
}

/// Navigation chrome for screen previews: the title and the toolbar are part of the screen, so a
/// snapshot has to include them.
///
/// Inside the storybook these toolbars end up in the app's own navigation bar rather than in the
/// card — SwiftUI hoists `.toolbar` out of the scaled card, and dropping this stack only makes
/// that worse, since a toolbar with no local container has nowhere else to go. The storybook hides
/// its root bar instead.
private struct NavigationHost<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack { content }
    }
}
