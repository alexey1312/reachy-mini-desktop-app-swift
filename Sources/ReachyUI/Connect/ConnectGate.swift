import ReachyKit
import SwiftUI

/// Connecting, with the whole screen to do it in.
///
/// A tab bar over an unconnected robot offered four destinations that could not
/// answer anything; removing it is what lets this flow use the full width and a
/// large title. `ConnectionScreen` itself is untouched — its five sections and
/// their section-by-section suppression are load-bearing and documented there.
struct ConnectGate: View {
    let session: RobotSession
    let router: ReachyRouter

    var body: some View {
        @Bindable var router = router
        return NavigationStack {
            ConnectionScreen(session: session, showRemoteRobots: { router.showsRemoteRobots = true })
                .navigationTitle("Connect")
                .hfAccountToolbar(isPresented: $router.showsAccount)
        }
    }
}
