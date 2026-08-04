import ReachyKit
import SwiftUI

/// Entry point for the shared UI: connection flow → robot control, with one live
/// viewport placed according to how much room there is.
///
/// The tab bar lives here rather than in the app target because the Live tab and
/// the Robot tab share a `RobotSession` and a `ViewportModel`, and because
/// whether Live exists at all depends on the size class — which an `App` cannot
/// read. Diagnostics is injected so the app target keeps owning its own screen
/// without a second, nested tab bar.
public struct ReachyRootView<Diagnostics: View>: View {
    private enum TabID: Hashable {
        case robot
        case live
        case diagnostics
    }

    @State private var session: RobotSession
    @State private var viewport: ViewportModel
    @State private var tab: TabID = .robot
    @State private var showsSettings = false
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

    private let diagnostics: Diagnostics

    @MainActor
    public init(@ViewBuilder diagnostics: () -> Diagnostics) {
        self.init(session: RobotSession(), diagnostics: diagnostics)
    }

    /// Internal so previews can park the root in a phase a real connection would have to reach.
    @MainActor
    init(
        session: RobotSession,
        viewport: ViewportModel = ViewportModel(),
        @ViewBuilder diagnostics: () -> Diagnostics
    ) {
        _session = State(initialValue: session)
        _viewport = State(initialValue: viewport)
        self.diagnostics = diagnostics()
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
            Tab("Diagnostics", systemImage: "stethoscope", value: TabID.diagnostics) {
                diagnostics
            }
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

    // MARK: - Tabs

    @ViewBuilder
    private var robotTab: some View {
        switch session.phase {
        case .idle, .connecting:
            ConnectionScreen(session: session)
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
