import ReachyDesign
import ReachyKit
import ReachyMedia
import SwiftUI

/// The connected interface: five tabs that are always there.
///
/// `.sidebarAdaptable` is iOS 18 / macOS 15 — on the deployment floor, not an
/// iOS 26 API — and it replaces the hand-written `HStack { viewport | Divider |
/// column }` the root used to build for a regular width. Five unconditional tabs
/// are what make it possible: a sidebar cannot adapt around a destination that
/// appears and disappears under it.
struct ReachyTabShell: View {
    let session: RobotSession
    let viewport: ViewportModel
    let floating: FloatingViewportModel
    let runningApp: RunningAppModel
    let router: ReachyRouter
    let remoteLink: RemoteRobotLink?
    let findRobot: () -> Void

    /// The store's two models live here rather than inside the Apps tab because the
    /// dock expands into the *same* page a store row opens, and it does so from
    /// every tab. One copy, or the two surfaces disagree about what is installed the
    /// moment either one acts. They are inert until `load()`, so holding them for
    /// the life of a connection costs nothing — and a connection is exactly how long
    /// the caches behind them live.
    @State private var store: AppStoreModel
    @State private var install: AppInstallModel

    init(
        session: RobotSession,
        viewport: ViewportModel,
        floating: FloatingViewportModel,
        runningApp: RunningAppModel,
        router: ReachyRouter,
        remoteLink: RemoteRobotLink?,
        findRobot: @escaping () -> Void
    ) {
        self.session = session
        self.viewport = viewport
        self.floating = floating
        self.runningApp = runningApp
        self.router = router
        self.remoteLink = remoteLink
        self.findRobot = findRobot
        _store = State(initialValue: AppStoreModel(session: session))
        _install = State(initialValue: AppInstallModel(session: session))
    }

    var body: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            Tab(value: ReachyRouter.Tab.robot) {
                RobotTab(session: session, router: router)
            } label: {
                Label(.reachy("Robot"), systemImage: "figure.wave")
            }
            Tab(value: ReachyRouter.Tab.live) {
                LiveTab(
                    session: session,
                    viewport: viewport,
                    floating: floating,
                    router: router,
                    remoteLink: remoteLink
                )
            } label: {
                Label(.reachy("Live"), systemImage: "cube.transparent")
            }
            Tab(value: ReachyRouter.Tab.moves) {
                MovesTab(session: session, router: router)
            } label: {
                Label(.reachy("Moves"), systemImage: "music.note")
            }
            Tab(value: ReachyRouter.Tab.apps) {
                AppsTab(
                    session: session,
                    router: router,
                    runningApp: runningApp,
                    store: store,
                    install: install,
                    findRobot: findRobot
                )
            } label: {
                Label(.reachy("Apps"), systemImage: "square.grid.2x2")
            }
            Tab(value: ReachyRouter.Tab.settings) {
                SettingsTab(session: session, router: router)
            } label: {
                Label(.reachy("Settings"), systemImage: "gearshape")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The bar gets out of the way while reading a list and comes back on the way
        // up. iPhone only, and the fork lives in `ReachyChrome` — a sidebar has
        // nothing to minimise.
        //
        // Off while the dock is up. The dock is an opaque strip in the bottom safe
        // area, so a minimised bar shrinks into a row it cannot be seen in: the
        // whole tab bar disappeared the moment a list was scrolled down with an app
        // running, and it read as the dock having replaced it. Getting one row back
        // is not worth losing every destination.
        .reachyMinimizingTabBar(runningApp.visibleStatus(for: session) == nil)
        // Above `runningAppDock` on purpose: the dock is a bottom `safeAreaInset`,
        // and applying it afterwards is what shrinks the area the window comes to
        // rest in. The other order parks the window on the dock's buttons.
        //
        // The router is read here rather than inside the model: `placement` is a
        // function of which tab is showing, and this is the one place that knows.
        .onChange(of: router.tab, initial: true) { _, tab in
            floating.isLiveTabSelected = tab == .live
        }
        .floatingViewport(model: floating, viewport: viewport, session: session) {
            router.tab = .live
        }
        // Applied to the `TabView` itself — see `runningAppDock` for why that is the
        // whole trick. It is not mounted in the gate: with no connection
        // `RunningAppModel.canPoll` is false and the dock draws `EmptyView`, so the
        // polling should die with the shell rather than idle behind the gate.
        .runningAppDock(session: session, model: runningApp, store: store, install: install)
    }
}
