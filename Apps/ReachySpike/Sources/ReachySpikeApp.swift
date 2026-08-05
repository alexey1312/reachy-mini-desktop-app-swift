import ReachyUI
import SwiftUI

@main
struct ReachySpikeApp: App {
    var body: some Scene {
        WindowGroup {
            // The tab bar is `ReachyRootView`'s: which tabs exist depends on the
            // size class, and the robot tabs share one session. This screen is not
            // one of them — it is handed to Settings → Advanced, where a phase 0
            // device check belongs now that connecting is a first-class flow.
            ReachyRootView {
                SpikeView()
            }
        }
    }
}
