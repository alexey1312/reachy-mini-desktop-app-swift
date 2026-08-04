import ReachyKit
import SwiftUI

/// Live daemon log console (journalctl tail over WebSocket).
struct LogConsoleScreen: View {
    let address: RobotAddress

    @State private var model = LogConsoleModel()
    @State private var setupError: String?

    var body: some View {
        LogConsoleView(
            model: model,
            source: address.displayString,
            emptyDescription: "Daemon logs come from journalctl on the robot — the local simulator has none.",
            failure: setupError
        )
        .navigationTitle("Daemon logs")
        .task { await stream() }
    }

    /// `.task` cancels the stream when the screen goes away — no manual task handle.
    private func stream() async {
        do {
            let client = try LogStreamClient(address: address)
            for await chunk in client.lines() {
                model.ingest(chunk)
            }
        } catch {
            setupError = "\(error)"
        }
    }
}
