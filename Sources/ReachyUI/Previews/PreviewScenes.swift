import HuggingFaceAuth
import ReachyKit
import ReachyMedia
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

    /// An account parked in one state, for the toolbar button and the sheet behind
    /// it. Goes through `HFSignInModel.preview`, which is where the token fixtures
    /// that make each state coherent already live.
    static func account(in state: HFAccount.State) -> HFAccount {
        HFSignInModel.preview(state: state).account
    }

    static func robotScreen(_ session: RobotSession) -> some View {
        NavigationHost {
            RobotScreen(session: session)
        }
        .preview()
    }

    /// The account button in a bar of its own. A whole root would capture the button at two
    /// pixels' worth of a full screen; this is what makes each state legible.
    static func accountToolbar(_ state: HFAccount.State) -> some View {
        NavigationHost {
            Text("Robot")
                .navigationTitle("Reachy Mini")
                .hfAccountToolbar(isPresented: .constant(false))
        }
        .environment(account(in: state))
        .preview()
    }

    /// The rail with its header, on its own. Worth capturing apart from the screen:
    /// on a full gate capture it is a strip a tenth of the frame tall, and the seven
    /// states it distinguishes are the whole reason it exists.
    static func rail(
        _ step: RobotSession.ConnectionStep,
        powerTransition: RobotSession.PowerTransition? = nil
    ) -> some View {
        ConnectHeader(
            session: .preview(phase: .connecting(step), powerTransition: powerTransition),
            displayed: .connecting(step)
        )
        .preview()
    }

    /// The two ends of the walk, which no `ConnectionStep` can express: nothing
    /// attempted yet, and every stage done. The second is the frame `holdsGate`
    /// exists to keep on screen.
    static func rail(_ phase: RobotSession.ConnectionPhase) -> some View {
        ConnectHeader(session: .preview(phase: phase), displayed: phase)
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

    // The app-store and running-app wrappers live in `PreviewAppScenes.swift` —
    // this file is at its length limit.

    static func logConsole(
        _ model: LogConsoleModel? = nil,
        setupError: String? = nil,
        session: RobotSession? = nil
    ) -> some View {
        NavigationHost {
            LogConsoleScreen(
                session: session ?? .preview(),
                model: model ?? .preview(),
                setupError: setupError
            )
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
        driver: TeleopDriver? = nil,
        setupError: String? = nil
    ) -> some View {
        NavigationHost {
            ControllerScreen(
                session: session,
                driver: driver ?? TeleopDriver(),
                setupError: setupError
            )
        }
        .preview()
    }

    /// Enough to hang the joystick and its return-to-neutral button on a camera
    /// preview: what offers them is the factory being *present*, not it being
    /// callable. Nothing ever calls this one — `connectTeleop` returns early in
    /// preview mode — so throwing is the honest body rather than a limitation.
    static let teleopFactory: TeleopFactory = { throw ReachyKitError.teleopUnavailable }

    /// `makeTeleop` decides whether the joystick is offered at all, so it is a
    /// preview knob rather than something derived here.
    static func viewport(
        _ model: ViewportModel,
        offersCamera: Bool = true,
        makeTeleop: TeleopFactory? = nil
    ) -> some View {
        ViewportView(model: model, offersCamera: offersCamera, makeTeleop: makeTeleop)
            .preview()
    }

    /// The floating window over a screen-shaped hole, so the corner it rests in is
    /// part of the capture rather than something to take on trust.
    ///
    /// `bounds` comes from the container rather than from a real safe area: the
    /// placement arithmetic is covered by `FloatingViewportModelTests`, and what a
    /// reference adds is the window's own size, shape and chrome.
    static func floatingViewport(
        _ model: FloatingViewportModel,
        viewport: ViewportModel? = nil,
        session: RobotSession? = nil
    ) -> some View {
        GeometryReader { geometry in
            FloatingViewport(
                model: model,
                viewport: viewport ?? .preview(),
                session: session ?? .preview(),
                bounds: CGRect(origin: .zero, size: geometry.size),
                open: {}
            )
        }
        .frame(width: 320, height: 460)
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

    /// `route` is a parameter because the segments are now the screen's shape: a
    /// capture of one says nothing about the other two.
    ///
    /// The progress model is always zero-dwell. With a real one the screen's
    /// `onChange` would queue the phase and the capture would land on whichever
    /// frame the drain happened to be on — the same timing dependence the spinner
    /// previews already have, and avoidable here.
    static func connection(
        _ session: RobotSession,
        route: ConnectRoute = .network,
        browser: RobotBrowser? = nil,
        manualInput: String = "",
        knownRobots: KnownRobotsModel? = nil
    ) -> some View {
        ConnectionScreen(
            session: session,
            progress: ConnectProgressModel(dwell: .zero),
            browser: browser ?? .preview(names: []),
            manualInput: manualInput,
            knownRobots: knownRobots ?? .preview([]),
            route: route,
            // Always supplied, unlike `showRemoteRobots`: the gate always offers this
            // and there is no state in which it should be missing, so a reference
            // without the row would be defending a screen the app never draws.
            showPermissions: {}
        )
        .preview()
    }

    /// `hfAccount` is injectable because the account button now sits in every
    /// tab's bar: without one every root capture would show only the signed-out
    /// state.
    static func root(
        _ session: RobotSession,
        viewport: ViewportModel? = nil,
        floating: FloatingViewportModel? = nil,
        tab: ReachyRouter.Tab = .robot,
        hfAccount: HFAccount? = nil,
        remoteLink: RemoteRobotLink? = nil
    ) -> some View {
        ReachyRootView(
            session: session,
            viewport: viewport ?? .preview(),
            floating: floating,
            hfAccount: hfAccount,
            tab: tab,
            remoteLink: remoteLink
        ) {
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

// `NavigationHost` and `View.preview()` live in `PreviewHost.swift` — they were
// file-private here, which is what stopped the scenes being split across two files.
