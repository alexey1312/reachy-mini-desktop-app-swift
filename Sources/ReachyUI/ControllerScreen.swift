import ReachyKit
import SwiftUI

/// Live teleop: joystick drives head yaw/pitch, sliders the rest.
/// Targets stream over `ws/set_target`; the daemon clamps safety limits.
struct ControllerScreen: View {
    let address: RobotAddress

    @State private var client: SetTargetClient?
    @State private var target = SetTargetClient.Target()
    @State private var setupError: String?

    // Comfortable UI ranges; hardware limits (clamped by the daemon anyway):
    // head pitch/roll ±40°, yaw ±180°, body yaw ±180°
    private let headAngle = 40.0 * .pi / 180
    private let fullTurn = 180.0 * .pi / 180
    private let antennaRange = 150.0 * .pi / 180

    var body: some View {
        Form {
            Section("Head — drag: yaw / pitch") {
                JoystickPad { x, y in
                    target.yaw = -x * headAngle
                    target.pitch = y * headAngle
                    push()
                }
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Head") {
                slider("Roll", value: $target.roll, range: -headAngle ... headAngle, format: .degrees)
                slider("Height", value: $target.z, range: -0.03 ... 0.03, format: .millimeters)
            }
            Section("Body") {
                slider("Body yaw", value: $target.bodyYaw, range: -fullTurn ... fullTurn, format: .degrees)
            }
            Section("Antennas") {
                slider("Left", value: $target.antennaLeft, range: -antennaRange ... antennaRange, format: .degrees)
                slider("Right", value: $target.antennaRight, range: -antennaRange ... antennaRange, format: .degrees)
            }
            Section {
                Button("Reset to neutral") {
                    target = .init()
                    push()
                }
            }
            if let setupError {
                Section {
                    Text(setupError)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Controller")
        .onAppear { start() }
        .onDisappear {
            let client = client
            Task { await client?.disconnect() }
        }
    }

    private enum SliderFormat { case degrees, millimeters }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: SliderFormat
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(formatted(value.wrappedValue, as: format))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = $0; push() }
            ), in: range)
        }
    }

    private func formatted(_ value: Double, as format: SliderFormat) -> String {
        switch format {
        case .degrees: String(format: "%.0f°", value * 180 / .pi)
        case .millimeters: String(format: "%.0f mm", value * 1000)
        }
    }

    private func start() {
        do {
            let client = try SetTargetClient(address: address)
            self.client = client
            Task { await client.connect() }
        } catch {
            setupError = "\(error)"
        }
    }

    private func push() {
        guard let client else { return }
        let target = target
        Task { await client.send(target) }
    }
}
