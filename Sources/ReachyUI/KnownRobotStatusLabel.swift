import SwiftUI

/// Whether a robot this app has met before is answering right now.
///
/// Lives with the status rather than inside the connection screen: it is a
/// rendering of `KnownRobotsModel.Status`, and nothing about it is specific to
/// the screen that happens to show the list.
struct KnownRobotStatusLabel: View {
    let status: KnownRobotsModel.Status

    var body: some View {
        switch status {
        case .checking:
            ProgressView()
        case .reachable:
            Text("On the network")
                .font(.caption)
                .foregroundStyle(.green)
        case .unreachable:
            Text("Not responding")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
