import ReachyDesign
import ReachyKit
import SwiftUI

/// Picks one robot out of everything advertising the provisioning service.
///
/// Every robot advertises the same local name, so the list is ordered by signal strength
/// and says so — until one is connected there is nothing else to tell them apart by.
struct OnboardingScanStep: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingStepScaffold(
            title: "Find the robot",
            message: message
        ) {
            switch model.availability {
            case .ready, .unknown:
                results
            case .poweredOff:
                unavailable(
                    "Bluetooth is switched off",
                    detail: "Turn it on in Control Centre or Settings, and this list will fill in."
                )
            case .unauthorized:
                unavailable(
                    "This app can't use Bluetooth",
                    detail: "Allow Bluetooth for this app in Settings, then come back."
                )
                #if os(iOS)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                #endif
            case .unsupported:
                unavailable(
                    "This device has no Bluetooth",
                    detail: "The iOS Simulator never has any. Set the robot up from a real device, or join "
                        + "its own reachy-mini-ap network and configure it over Wi-Fi instead."
                )
            }
            // Only where the panel above has not already said it. An unusable radio makes
            // the scan fail with the same sentence, and printing it again underneath in
            // red reads as a second, worse problem.
            if radioIsUsable {
                OnboardingErrorText(message: model.errorMessage)
            }
        } actions: {
            if let only = model.discovered.first, model.discovered.count == 1 {
                Button("Connect to this robot") {
                    Task { await model.connect(to: only.id) }
                }
                .reachyButton(.prominent)
                .frame(maxWidth: .infinity)
                .disabled(model.isBusy)
            }
            OnboardingBackButton(model: model)
        }
    }

    private var radioIsUsable: Bool {
        model.availability == .ready || model.availability == .unknown
    }

    private var message: String {
        switch model.availability {
        case .ready, .unknown:
            "Robots all advertise the same name, so they are listed by signal strength. "
                + "The nearest one is at the top."
        default:
            "Setting a robot up needs Bluetooth."
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.discovered.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching…")
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(model.discovered) { robot in
            Button {
                Task { await model.connect(to: robot.id) }
            } label: {
                LabeledContent {
                    if model.isBusy {
                        ProgressView()
                    } else {
                        Text("\(robot.rssi) dBm")
                            .font(.caption.monospaced())
                    }
                } label: {
                    Label(robot.name, systemImage: "dot.radiowaves.left.and.right")
                }
            }
            .reachyButton()
            .disabled(model.isBusy)
        }
    }

    private func unavailable(_ title: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: "antenna.radiowaves.left.and.right.slash", description: Text(detail))
    }
}
