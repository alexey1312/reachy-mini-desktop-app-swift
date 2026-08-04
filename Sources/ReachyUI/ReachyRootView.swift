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

    @State private var session = RobotSession()
    @State private var viewport = ViewportModel()
    @State private var tab: TabID = .robot
    @State private var showsAudioSettings = false
    @Environment(\.scenePhase) private var scenePhase

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

    public init(@ViewBuilder diagnostics: () -> Diagnostics) {
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
            if let viewportAddress {
                viewport.attach(to: viewportAddress)
            } else {
                viewport.detach()
            }
        }
        .onChange(of: viewportIsOnScreen, initial: true) { _, onScreen in
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
        if viewportAddress != nil {
            ViewportView(model: viewport, offersCamera: session.hasCamera)
        } else {
            ContentUnavailableView(
                "No live view",
                systemImage: "cube.transparent",
                description: Text("Start the robot backend to see the model and the camera.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var liveTab: some View {
        NavigationStack {
            // No `ignoresSafeArea` here: the camera hangs its joystick off a
            // bottom safe-area inset, which would then be laid out under the tab
            // bar and clipped.
            ViewportView(model: viewport, offersCamera: session.hasCamera)
                .navigationTitle("Live")
                .toolbar {
                    ToolbarItem {
                        Button {
                            showsAudioSettings = true
                        } label: {
                            Label("Audio", systemImage: "speaker.wave.2")
                        }
                    }
                }
                .sheet(isPresented: $showsAudioSettings) {
                    NavigationStack {
                        Form { AudioSettingsSection(session: session, header: nil) }
                            .formStyle(.grouped)
                            .navigationTitle("Audio")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { showsAudioSettings = false }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                }
        }
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
    /// thing the user is actually looking at.
    private var viewportIsOnScreen: Bool {
        guard scenePhase == .active, viewportAddress != nil else { return false }
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
}
