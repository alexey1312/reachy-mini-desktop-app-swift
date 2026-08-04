import ReachyUI
import SwiftUI

@main
struct ReachySpikeApp: App {
    var body: some Scene {
        WindowGroup {
            // The tab bar is `ReachyRootView`'s: which tabs exist depends on the
            // size class, and the robot tabs share one session.
            ReachyRootView {
                SpikeView()
            }
        }
    }
}
