import SwiftUI

/// Stands between opening the flow and the first CoreBluetooth call, so the system's
/// Bluetooth prompt arrives on a screen that has already said what it is for.
struct OnboardingWelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingStepScaffold(
            title: "Before you start",
            message: "A new robot has no network yet, so the first conversation happens over Bluetooth. "
                + "It takes a couple of minutes."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                requirement(
                    "The robot, powered on",
                    detail: "Give it about a minute after switching on before it starts advertising.",
                    icon: "power"
                )
                requirement(
                    "The last five characters of its serial number",
                    detail: "The serial is printed on the robot. Capitals matter, and it is not always digits.",
                    icon: "numbers.rectangle"
                )
                requirement(
                    "Your Wi-Fi password",
                    detail: "It is encrypted for the robot before it leaves this device.",
                    icon: "wifi"
                )
                Label(
                    "The next screen turns on Bluetooth scanning, so iOS will ask for permission.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } actions: {
            Button("Start") {
                model.beginScan()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }

    private func requirement(_ title: String, detail: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.tint)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
