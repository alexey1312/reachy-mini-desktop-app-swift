import ReachyKit
import SwiftUI

/// Robot software updates from settings, as opposed to the blocking
/// `DaemonUpdateScreen` a too-old daemon lands on. Same model, same log.
struct SystemUpdateCard: View {
    let session: RobotSession

    @State private var model: SystemUpdateModel?
    @AppStorage("update.preRelease") private var preRelease = false
    @State private var showsLog = false

    /// An injected model is also what keeps the `.task` below inert — it only builds one
    /// when there is none, so a preview never reaches the network.
    @MainActor
    init(session: RobotSession, model: SystemUpdateModel? = nil) {
        self.session = session
        _model = State(initialValue: model)
    }

    var body: some View {
        Section {
            statusRow
            Toggle("Include pre-release versions", isOn: $preRelease)
                .disabled(model?.isBusy ?? true)
                .onChange(of: preRelease) { _, newValue in
                    Task { await model?.check(preRelease: newValue) }
                }
            actions
        } header: {
            Text("System update")
        } footer: {
            Text("The robot downloads updates itself and restarts when one finishes.")
        }
        .task {
            guard model == nil else { return }
            model = SystemUpdateModel(session: session)
        }
        .sheet(isPresented: $showsLog) {
            if let model {
                NavigationStack {
                    LogConsoleView(
                        model: model.log,
                        source: session.address?.displayString ?? "robot",
                        emptyDescription: "The robot has not sent any installer output yet."
                    )
                    .navigationTitle("Update log")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showsLog = false }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model?.state ?? .idle {
        case .idle:
            LabeledContent("Installed", value: session.lastStatus?.version ?? "—")
        case .checking:
            Label("Checking for updates…", systemImage: "arrow.triangle.2.circlepath")
        case let .upToDate(current):
            Label("Up to date — \(current)", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case let .robotOffline(current):
            Label("\(current) — the robot can't reach the internet", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.orange)
        case let .available(current, latest):
            LabeledContent("Update available") { Text("\(current) → \(latest)").monospaced() }
        case .installing:
            Label("Installing — this takes a minute or two…", systemImage: "arrow.down.circle")
        case .restarting:
            Label("The robot is restarting…", systemImage: "arrow.clockwise")
        case let .finished(version):
            Label("Updated to \(version).", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if case .available = model?.state {
            Button("Update now") {
                Task { await model?.install(preRelease: preRelease) }
            }
        } else if !(model?.isBusy ?? true) {
            Button("Check for updates") {
                Task { await model?.check(preRelease: preRelease) }
            }
        }
        if model?.log.entries.isEmpty == false {
            Button("Show installer log") { showsLog = true }
        }
    }
}
