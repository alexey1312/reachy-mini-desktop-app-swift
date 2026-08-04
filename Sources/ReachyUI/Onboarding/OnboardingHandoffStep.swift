import ReachyKit
import SwiftUI

/// Ends the Bluetooth session and hands the robot to the ordinary network sweep.
///
/// The hardware id is the whole point of this screen: the robot is about to appear at an
/// address nobody has seen yet, and its identity is the only thing that carries across
/// (rule 4).
struct OnboardingHandoffStep: View {
    let model: OnboardingModel
    var onFinish: (OnboardingOutcome) -> Void

    var body: some View {
        OnboardingStepScaffold(
            title: "All set",
            message: "Bluetooth's job is done. The app will pick the robot up on the network from here."
        ) {
            if let hardwareID = model.session?.hardwareID {
                LabeledContent("Hardware ID") {
                    Text(hardwareID)
                        .font(.caption.monospaced())
                }
            }
            if let address = model.session?.robotAddress {
                LabeledContent("Address") {
                    Text(address)
                        .font(.caption.monospaced())
                }
            }
            Label(
                "If this phone is on the robot's own reachy-mini-ap network, switch it back to your home Wi-Fi now.",
                systemImage: "wifi.router"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Label(
                "You can give the robot a name in Settings once it is connected.",
                systemImage: "tag"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button("Done") {
                onFinish(model.finish())
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }
}
