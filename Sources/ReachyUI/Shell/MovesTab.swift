import ReachyKit
import SwiftUI

/// Recorded moves at the root of a tab rather than two taps into a `Form`.
struct MovesTab: View {
    let session: RobotSession
    let router: ReachyRouter

    var body: some View {
        @Bindable var router = router
        return NavigationStack {
            Group {
                if session.canPlayMoves {
                    MovesScreen(session: session)
                } else {
                    MovesUnavailableView()
                }
            }
            .hfAccountToolbar(isPresented: $router.showsAccount)
        }
    }
}
