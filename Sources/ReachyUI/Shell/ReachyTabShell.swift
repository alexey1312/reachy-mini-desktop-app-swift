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
    let runningApp: RunningAppModel
    let router: ReachyRouter
    let remoteLink: RemoteRobotLink?
    let findRobot: () -> Void

    var body: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            Tab("Robot", systemImage: "figure.wave", value: ReachyRouter.Tab.robot) {
                RobotTab(session: session, router: router)
            }
            Tab("Live", systemImage: "cube.transparent", value: ReachyRouter.Tab.live) {
                LiveTab(session: session, viewport: viewport, router: router, remoteLink: remoteLink)
            }
            Tab("Moves", systemImage: "music.note", value: ReachyRouter.Tab.moves) {
                MovesTab(session: session, router: router)
            }
            Tab("Apps", systemImage: "square.grid.2x2", value: ReachyRouter.Tab.apps) {
                AppsTab(session: session, router: router, findRobot: findRobot)
            }
            Tab("Settings", systemImage: "gearshape", value: ReachyRouter.Tab.settings) {
                SettingsTab(session: session, router: router)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The bar gets out of the way while reading a list and comes back on the way
        // up. iPhone only, and the fork lives in `ReachyChrome` — a sidebar has
        // nothing to minimise.
        .reachyMinimizingTabBar()
        // Applied to the `TabView` itself — see `runningAppDock` for why that is the
        // whole trick. It is not mounted in the gate: with no connection
        // `RunningAppModel.canPoll` is false and the dock draws `EmptyView`, so the
        // polling should die with the shell rather than idle behind the gate.
        .runningAppDock(session: session, model: runningApp)
    }
}
