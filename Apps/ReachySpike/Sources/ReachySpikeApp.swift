import ReachyUI
import SwiftUI

@main
struct ReachySpikeApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ReachyRootView()
                    .tabItem { Label("Robot", systemImage: "figure.wave") }
                SpikeView()
                    .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            }
        }
    }
}
