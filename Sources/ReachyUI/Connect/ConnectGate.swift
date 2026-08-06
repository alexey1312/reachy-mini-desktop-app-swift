import ReachyDesign
import ReachyKit
import SwiftUI

/// Connecting, with the whole screen to do it in.
///
/// A tab bar over an unconnected robot offered four destinations that could not
/// answer anything; removing it is what lets this flow use the full width and a
/// large title.
///
/// `progress` is handed down rather than made here. It has to outlive this view:
/// the root replaces the gate the moment the phase turns `.connected`, and the
/// whole point of the model is to decide when that may happen.
struct ConnectGate: View {
    let session: RobotSession
    let router: ReachyRouter
    let progress: ConnectProgressModel

    var body: some View {
        @Bindable var router = router
        return NavigationStack {
            ConnectionScreen(
                session: session,
                progress: progress,
                showRemoteRobots: { router.showsRemoteRobots = true },
                showPermissions: { router.showsPermissions = true }
            )
            // A `Form` left to itself fills a 1024 pt iPad, and rows a metre
            // wide with three words in them read as a broken layout. Nothing
            // constrained this before because the tab bar's column did.
            .frame(maxWidth: Metrics.readableForm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Constraining the form leaves its grouped backdrop as a column
            // with the window's own background either side of it. This is the
            // same semantic style the form paints, so the two cannot disagree
            // about the appearance — the trap `AGENTS.md` records is a *pinned*
            // colour, and there is none here.
            .groupedPageBackground()
            .navigationTitle(.reachy("Connect"))
            .hfAccountToolbar(isPresented: $router.showsAccount)
        }
    }
}

extension View {
    /// The backdrop a grouped `Form` paints for itself, behind a whole page.
    ///
    /// Only iOS has one to name: `.formStyle(.grouped)` on macOS lays out against
    /// the window's own background and has nothing to match.
    func groupedPageBackground() -> some View {
        #if os(iOS)
            background(Color(.systemGroupedBackground))
        #else
            self
        #endif
    }
}
