import ReachyDesign
import SwiftUI

/// Whether a robot this app has met before is answering right now.
///
/// Lives with the status rather than inside the connection screen: it is a
/// rendering of `KnownRobotsModel.Status`, and nothing about it is specific to
/// the screen that happens to show the list.
///
/// This is the one place `StatusTone.active` earns its colour. On a strip or a
/// widget tile "Running" is already obvious from the surface being there at all;
/// in a list of robots the reader is scanning for exactly this, so the reachable
/// one is the only thing that should catch the eye.
struct KnownRobotStatusLabel: View {
    let status: KnownRobotsModel.Status

    var body: some View {
        switch status {
        case .checking:
            ProgressView()
        case .reachable:
            ReachyStatusLabel(text: "On the network", tone: .active)
        case .unreachable:
            ReachyStatusLabel(text: "Not responding", tone: .idle)
        }
    }
}
