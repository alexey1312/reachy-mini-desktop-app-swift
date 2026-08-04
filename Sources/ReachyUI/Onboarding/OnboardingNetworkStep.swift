import ReachyKit
import SwiftUI

/// Chooses the network and takes the password.
///
/// "Other network…" is a permanent row, not an escape hatch: the robot answers a scan in
/// one 180-byte message with no pagination and no flag saying anything was dropped, so a
/// missing network is the ordinary case rather than the broken one.
struct OnboardingNetworkStep: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingStepScaffold(
            title: "Choose a network",
            message: "The robot joins this network and then talks to the app over it. "
                + "Bluetooth is only here to get it that far."
        ) {
            if model.isAlreadyOnNetwork {
                alreadyConnected
            }
            picker
            if model.selectedSSID == nil {
                TextField("Network name", text: Binding(get: { model.manualSSID }, set: { model.manualSSID = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
            }
            SecureField("Wi-Fi password", text: Binding(get: { model.password }, set: { model.password = $0 }))
                .textFieldStyle(.roundedBorder)
            Text("The robot fits only a handful of names into one Bluetooth message and cannot say how many it left "
                + "out, so a network missing from the list is normal — type it in under \"Other network…\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(
                "The password is encrypted for this robot before it is sent, but someone within Bluetooth range "
                    + "could still interfere with the exchange. Set the robot up somewhere you trust.",
                systemImage: "lock.trianglebadge.exclamationmark"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            OnboardingErrorText(message: model.errorMessage)
        } actions: {
            Button("Send to the robot") {
                Task { await model.join() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!model.canJoin)
            OnboardingBackButton(model: model)
        }
    }

    private var picker: some View {
        HStack {
            Picker("Network", selection: Binding(get: { model.selectedSSID }, set: { model.selectedSSID = $0 })) {
                ForEach(model.networks, id: \.self) { network in
                    Text(network).tag(String?.some(network))
                }
                Text("Other network…").tag(String?.none)
            }
            .pickerStyle(.menu)
            Spacer()
            Button {
                Task { await model.loadNetworks() }
            } label: {
                if model.isBusy {
                    ProgressView()
                } else {
                    Label("Scan again", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
            }
            .disabled(model.isBusy)
        }
    }

    private var alreadyConnected: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This robot is already on a network.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
            Button("Keep it there and finish") {
                model.skipNetwork()
            }
        }
    }
}
