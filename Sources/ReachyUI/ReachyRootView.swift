import HuggingFaceAuth
import ReachyKit
import ReachyMedia
import SwiftUI

/// Entry point for the shared UI: connection flow → robot control, with one live
/// viewport placed according to how much room there is.
///
/// The tab bar lives here rather than in the app target because the Live tab and
/// the Robot tab share a `RobotSession` and a `ViewportModel`, and because
/// whether Live exists at all depends on the size class — which an `App` cannot
/// read. The app target's own developer screen is injected and handed to
/// Settings, so it keeps owning that screen without a tab or a nested tab bar.
public struct ReachyRootView<Developer: View>: View {
    private enum TabID: Hashable {
        case robot
        case live
        case apps
    }

    @State private var session: RobotSession
    @State private var viewport: ViewportModel
    /// One Hugging Face session for the whole app, restored from the Keychain on
    /// launch and handed down through the environment — the account outlives any
    /// one robot connection, and several screens read it.
    @State private var hfAccount: HFAccount
    @State private var tab: TabID = .robot
    @State private var showsSettings = false
    /// The two ways to reach a robot are two entry points to the same list, so it
    /// is presented from here rather than owned by either screen that offers it.
    @State private var showsRemoteRobots = false
    /// Held for as long as the remote session is: dropping it would close the
    /// peer connection the session is talking over.
    @State private var remoteLink: RemoteRobotLink?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.reachyPreviewMode) private var previewMode

    #if os(macOS)
        /// `horizontalSizeClass` does not exist on macOS, where a window is always
        /// wide enough for the two-column layout.
        private var isCompact: Bool {
            false
        }
    #else
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        private var isCompact: Bool {
            horizontalSizeClass == .compact
        }
    #endif

    private let developer: Developer

    @MainActor
    public init(@ViewBuilder developer: () -> Developer) {
        self.init(session: RobotSession(), developer: developer)
    }

    /// Internal so previews can park the root in a phase a real connection would have to reach.
    @MainActor
    init(
        session: RobotSession,
        viewport: ViewportModel = ViewportModel(),
        hfAccount: HFAccount? = nil,
        @ViewBuilder developer: () -> Developer
    ) {
        _session = State(initialValue: session)
        _viewport = State(initialValue: viewport)
        _hfAccount = State(
            initialValue: hfAccount ?? HFAccount(store: KeychainHFTokenStore())
        )
        self.developer = developer()
    }

    public var body: some View {
        TabView(selection: $tab) {
            Tab("Robot", systemImage: "figure.wave", value: TabID.robot) {
                robotTab
            }
            if offersLiveTab {
                Tab("Live", systemImage: "cube.transparent", value: TabID.live) {
                    liveTab
                }
            }
            Tab("Apps", systemImage: "square.grid.2x2", value: TabID.apps) {
                appsTab
            }
        }
        .environment(\.reachyDeveloperScreen) { [developer] in AnyView(developer) }
        .environment(hfAccount)
        .sheet(isPresented: $showsRemoteRobots) {
            NavigationStack {
                YourReachiesScreen(
                    model: YourReachiesModel(
                        listing: CentralRelayClient { [hfAccount] in await hfAccount.currentToken() },
                        // `.needsReauth` also carries a username, so the state is
                        // the question, not whether a name is known.
                        isSignedIn: { [hfAccount] in
                            if case .signedIn = hfAccount.state {
                                true
                            } else {
                                false
                            }
                        }
                    ),
                    connect: connectRemotely,
                    // Pushed inside this sheet rather than sending the user to
                    // the robot's Settings: that screen is presented from the
                    // Live tab, which does not exist until a robot is connected —
                    // exactly the case that brings anyone here.
                    signIn: { HFSignInScreen(session: session, model: HFSignInModel(account: hfAccount)) }
                )
            }
        }
        .task {
            guard !previewMode else { return }
            hfAccount.restore()
        }
        .task(id: viewportAddress) {
            guard !previewMode else { return }
            if let viewportAddress {
                viewport.attach(to: viewportAddress)
            } else {
                viewport.detach()
            }
        }
        .onChange(of: viewportIsOnScreen, initial: true) { _, onScreen in
            guard !previewMode else { return }
            viewport.setActive(onScreen)
        }
        .onChange(of: offersLiveTab) { _, offered in
            // The tab it points at is about to stop existing; SwiftUI would pick
            // a replacement of its own, which lands on Diagnostics.
            if !offered, tab == .live {
                tab = .robot
            }
        }
    }

    /// Opens the relay session first, then hands the session a client that speaks
    /// over it. `start()` only begins asking central for a session — nothing has
    /// reached the robot yet, and the control channel's own deadline is what
    /// bounds the wait if it never answers.
    private func connectRemotely(to robot: CentralRobot) {
        showsRemoteRobots = false
        remoteLink?.stop()
        let link = RemoteRobotLink(
            robot: robot,
            relay: CentralRelayClient { [hfAccount] in await hfAccount.currentToken() }
        )
        remoteLink = link
        link.start()
        tab = .robot
        Task { await session.connect(using: link.client) }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var robotTab: some View {
        switch session.phase {
        case .idle, .connecting:
            ConnectionScreen(session: session, showRemoteRobots: { showsRemoteRobots = true })
        case .connected, .unreachable:
            if isCompact {
                NavigationStack { RobotScreen(session: session) }
            } else {
                HStack(spacing: 0) {
                    wideViewport
                    Divider()
                    NavigationStack {
                        RobotScreen(session: session)
                            .columnTitleStyle()
                    }
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 420)
                }
            }
        }
    }

    /// The store is its own destination rather than a row inside the robot screen:
    /// it is somewhere a user goes back to, and a widget can open it directly.
    private var appsTab: some View {
        NavigationStack {
            if session.canManageApps {
                AppStoreScreen(session: session)
            } else {
                // The catalogue is served by the daemon, not by the Hub — the robot
                // fetches it — so there is genuinely nothing to show without one.
                // Both ways to get one are offered, because "not on this network"
                // stopped meaning "out of reach".
                ContentUnavailableView {
                    Label("No robot connected", systemImage: "square.grid.2x2")
                } description: {
                    Text("Apps are installed on the robot, so this needs one connected.")
                } actions: {
                    Button("Find one nearby") { tab = .robot }
                    Button("Your Reachies") { showsRemoteRobots = true }
                }
                .navigationTitle("Apps")
            }
        }
    }

    @ViewBuilder
    private var wideViewport: some View {
        if viewportAddress == nil {
            ContentUnavailableView(
                "No live view",
                systemImage: "cube.transparent",
                description: Text("Start the robot backend to see the model and the camera.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.isAwake {
            ViewportView(model: viewport, offersCamera: session.hasCamera)
        } else {
            asleepViewport
        }
    }

    private var liveTab: some View {
        NavigationStack {
            // No `ignoresSafeArea` here: the camera hangs its joystick off a
            // bottom safe-area inset, which would then be laid out under the tab
            // bar and clipped.
            liveContent
                .navigationTitle("Live")
                .darkTitleBar()
                .toolbar {
                    ToolbarItem {
                        Button {
                            showsSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showsSettings) {
                    NavigationStack {
                        SettingsScreen(session: session)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { showsSettings = false }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                }
        }
    }

    /// Both streams would keep working while the robot sleeps — the camera hangs off
    /// `get_daemon` and the state stream off a running backend — but working is not the
    /// same as worth having. A motionless pose and a still frame cost the robot's radio
    /// and this phone's battery to show nothing, and a switcher between two inert views
    /// is a control that leads nowhere. So the tab keeps its place and offers the one
    /// thing that changes the situation.
    @ViewBuilder
    private var liveContent: some View {
        if session.isAwake {
            // Upwards only: the title bar above is pinned dark to match the black, while
            // the tab bar below is glass and has to keep materialising what every other
            // tab puts under it.
            ViewportView(model: viewport, offersCamera: session.hasCamera, backdropEdges: [.top, .horizontal])
        } else {
            asleepViewport
        }
    }

    private var asleepViewport: some View {
        AsleepBanner(session: session)
            .padding()
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Placement

    /// Only on iPhone: where there is room, the viewport sits beside the controls
    /// instead of behind a tab.
    private var offersLiveTab: Bool {
        isCompact && viewportAddress != nil
    }

    /// Both the geometry and the state routes sit behind the backend, so an
    /// address alone is not enough to show anything.
    private var viewportAddress: RobotAddress? {
        session.isBackendRunning ? session.address : nil
    }

    /// The single lever for battery: nothing streams unless the viewport is the
    /// thing the user is actually looking at — and a sleeping robot is never that,
    /// however visible the tab is.
    private var viewportIsOnScreen: Bool {
        guard scenePhase == .active, viewportAddress != nil, session.isAwake else { return false }
        return isCompact ? tab == .live : tab == .robot
    }
}

private extension View {
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

    /// The bar cannot take a background over the viewport — both
    /// `toolbarBackground(.visible:)` and its replacement `toolbarBackgroundVisibility`
    /// are ignored there — so its palette is pinned instead. Safe only because the content
    /// under it is pinned to match: on its own this put a white title on the 3D model's
    /// white backdrop.
    func darkTitleBar() -> some View {
        #if os(iOS)
            toolbarColorScheme(.dark, for: .navigationBar)
        #else
            self
        #endif
    }
}
