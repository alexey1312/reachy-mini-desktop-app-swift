import ReachyKit
import SwiftUI

/// The way back in when the network is not an option: a Bluetooth link to the robot, its
/// journal, and the scripts that undo whatever took it off the air.
struct BLEConsoleScreen: View {
    @State private var model = BLEConsoleModel()
    @State private var showsCommands = false

    var body: some View {
        Group {
            switch model.stage {
            case .scanning, .connecting:
                linkSetup
            case .locked, .unlocked:
                journal
            }
        }
        .navigationTitle("Recovery")
        .onAppear { model.startScan() }
        .onDisappear { model.stop() }
    }

    // MARK: - Getting a link

    private var linkSetup: some View {
        Form {
            Section {
                switch model.availability {
                case .ready, .unknown:
                    if model.discovered.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching over Bluetooth…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(model.discovered) { robot in
                        Button {
                            Task { await model.connect(to: robot.id) }
                        } label: {
                            LabeledContent(robot.name) {
                                Text("\(robot.rssi) dBm").font(.caption.monospaced())
                            }
                        }
                        .disabled(model.isBusy)
                    }
                case .poweredOff:
                    Label("Bluetooth is switched off.", systemImage: "antenna.radiowaves.left.and.right.slash")
                case .unauthorized:
                    Label("This app can't use Bluetooth.", systemImage: "hand.raised")
                case .unsupported:
                    Label("This device has no Bluetooth.", systemImage: "antenna.radiowaves.left.and.right.slash")
                }
            } header: {
                Text("Robot")
            } footer: {
                Text("Robots all advertise the same name, so they are listed by signal strength.")
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Linked

    private var journal: some View {
        // Deliberately no `failure:`. That replaces the list, and here the lines already
        // collected are the whole point — a feed that dies after six lines should leave
        // those six on screen, not swap them for an error.
        LogConsoleView(
            model: model.log,
            source: model.hardwareID ?? "bluetooth",
            emptyDescription: "The robot only logs when something happens. A quiet robot "
                + "sends nothing, and this stays empty."
        )
        .safeAreaInset(edge: .top) { notices }
        .toolbar {
            ToolbarItem {
                Button {
                    showsCommands = true
                } label: {
                    Label("Commands", systemImage: "wrench.and.screwdriver")
                }
            }
        }
        .sheet(isPresented: $showsCommands) {
            NavigationStack {
                BLERecoveryCommandsSheet(model: model)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showsCommands = false }
                        }
                    }
            }
        }
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Not a footnote. The robot slices its buffer well past what one Bluetooth
            // read can carry and throws away what it handed over, so lines genuinely
            // disappear here and nowhere else.
            Label(
                "Bluetooth drops journal lines when the robot logs faster than this can read. "
                    + "Once the robot is on the network, the Diagnostics console is the complete one.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            if model.journalFailure != nil {
                Divider()
                journalStopped
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    /// The robot's own `journalctl` exited. Nothing on this side can prevent it, and the
    /// text it answers with (`Journal not running`) means nothing to anyone who has not
    /// read the daemon — so say what happened and offer the one thing that helps.
    private var journalStopped: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("The robot stopped sending its log.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Start again") {
                model.restartJournal()
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }
}
