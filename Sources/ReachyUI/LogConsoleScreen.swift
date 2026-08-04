import ReachyKit
import SwiftUI

/// Live daemon log console (journalctl tail over WebSocket).
struct LogConsoleScreen: View {
    let address: RobotAddress

    @State private var model: LogConsoleModel
    @State private var setupError: String?
    @Environment(\.reachyPreviewMode) private var previewMode

    init(address: RobotAddress, model: LogConsoleModel = LogConsoleModel(), setupError: String? = nil) {
        self.address = address
        _model = State(initialValue: model)
        _setupError = State(initialValue: setupError)
    }

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
        guard !previewMode else { return }
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
