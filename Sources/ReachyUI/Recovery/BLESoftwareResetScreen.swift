import ReachyKit
import SwiftUI

/// The one command that destroys something the robot cannot get back.
///
/// Four gates, deliberately unalike — three copies of the same alert train a thumb to
/// dismiss all three. One is a claim to have understood, one is a value you have to
/// actually possess, one is a wait, and the last is a dialog that names the outcome.
struct BLESoftwareResetScreen: View {
    let model: BLEConsoleModel
    let script: BLERecoveryScript

    @State private var acknowledged = false
    @State private var typedID = ""
    @State private var code = ""
    @State private var countdown: Int?
    @State private var confirming = false
    @State private var dispatched = false
    @State private var stillAnswering: Bool?

    /// Long enough to interrupt a run of taps, short enough not to become its own ritual.
    private static let arming = 5

    var body: some View {
        Form {
            if dispatched {
                restoring
            } else {
                consequences
                gates
            }
        }
        .formStyle(.grouped)
        .navigationTitle(script.name)
        .onChange(of: gatesPassed, initial: true) { _, passed in
            countdown = passed ? Self.arming : nil
        }
        .task(id: countdown) {
            guard let value = countdown, value > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            countdown = value - 1
        }
        .confirmationDialog(
            "Erase the robot's software?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Erase and restore", role: .destructive) {
                Task { await dispatch() }
            }
        } message: {
            Text(script.summary)
        }
    }

    private var consequences: some View {
        Section("What this does") {
            bullet("Deletes the robot's Python environments outright.")
            bullet("Copies the factory set back from the robot's own restore directory.")
            bullet("Every app you installed, and everything those apps stored, is gone.")
            bullet("It takes about five minutes. Do not power the robot off during it.")
        }
    }

    @ViewBuilder
    private var gates: some View {
        Section {
            Toggle("I understand every installed app will be erased", isOn: $acknowledged)
        }
        Section {
            TextField("Hardware ID", text: $typedID)
                .font(.body.monospaced())
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
        } header: {
            Text("Confirm the robot")
        } footer: {
            if let hardwareID = model.hardwareID {
                Text("Type \(hardwareID) — this robot's id, shown so you are erasing the one in front of you.")
                    .font(.caption.monospaced())
            } else {
                Text("This robot did not report a hardware id, so it cannot be confirmed. Do not continue.")
            }
        }
        Section {
            SecureField("Robot's code", text: $code)
                .font(.body.monospaced())
        } header: {
            Text("Confirm it is you")
        } footer: {
            Text("Sent again the instant before the command goes out, so a session opened earlier for "
                + "something harmless cannot carry this through with it.")
        }
        Section {
            Button(role: .destructive) {
                confirming = true
            } label: {
                if let countdown, countdown > 0 {
                    Text("Erase and restore in \(countdown)…")
                } else {
                    Text("Erase and restore")
                }
            }
            .disabled(!gatesPassed || (countdown ?? Self.arming) > 0)
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var restoring: some View {
        Section("Restoring") {
            HStack(spacing: 10) {
                ProgressView()
                Text("This takes about five minutes. Leave the robot powered on.")
            }
            LabeledContent("Bluetooth") {
                switch stillAnswering {
                case true: Text("answering").foregroundStyle(.green)
                case false: Text("no answer").foregroundStyle(.orange)
                case nil: ProgressView()
                }
            }
            Text("The Bluetooth service is a separate unit and stays up throughout, so this only says the "
                + "robot is still there. Progress shows up in the journal when the daemon comes back.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .task {
            while !Task.isCancelled {
                stillAnswering = await model.isAnswering()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var gatesPassed: Bool {
        acknowledged && matchesHardwareID && code.count == BLEPinSession.length
    }

    /// Case and stray whitespace forgiven; the point is possession of the value, not
    /// transcription accuracy.
    private var matchesHardwareID: Bool {
        guard let hardwareID = model.hardwareID else { return false }
        return typedID.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(hardwareID) == .orderedSame
    }

    private func dispatch() async {
        let sent = await model.runGuarded(script, code: code)
        code = ""
        dispatched = sent
    }

    private func bullet(_ text: String) -> some View {
        Label(text, systemImage: "circle.fill")
            .labelStyle(BulletLabelStyle())
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}
