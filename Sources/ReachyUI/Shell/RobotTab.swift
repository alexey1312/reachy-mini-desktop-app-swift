import ReachyKit
import SwiftUI

struct RobotTab: View {
    let session: RobotSession
    let router: ReachyRouter

    var body: some View {
        @Bindable var router = router
        return NavigationStack {
            RobotScreen(session: session)
                .hfAccountToolbar(isPresented: $router.showsAccount)
        }
    }
}
