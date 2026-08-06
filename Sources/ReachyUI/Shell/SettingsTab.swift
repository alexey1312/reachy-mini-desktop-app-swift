import ReachyKit
import SwiftUI

/// Settings at the root of a tab. Both gears are gone with it: the push from the
/// robot screen and the sheet from the Live tab reached the same screen by two
/// different gestures, and neither is needed once it has a place of its own.
struct SettingsTab: View {
    let session: RobotSession
    let router: ReachyRouter

    var body: some View {
        @Bindable var router = router
        return NavigationStack {
            SettingsScreen(session: session)
                .hfAccountToolbar(isPresented: $router.showsAccount)
        }
    }
}
