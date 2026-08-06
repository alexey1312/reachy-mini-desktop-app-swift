import ReachyDesign
import ReachyKit
import SwiftUI

/// Connected-robot controls: identity, live daemon status, wake/sleep, audio.
///
/// The navigation container is the host's — this is a column on iPad and Mac and
/// a tab on iPhone, and both supply their own `NavigationStack`.
struct RobotScreen: View {
    let session: RobotSession

    var body: some View {
        Form {
            statusSection
            controlSection
            if let warning = session.compatibilityWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if let error = session.lastError {
                Section {
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button(.reachy("Disconnect"), role: .destructive) {
                    session.disconnect()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(identity?.name ?? "Robot")
    }

    private var identity: RobotIdentity? {
        switch session.phase {
        case let .connected(identity), let .unreachable(identity): identity
        default: nil
        }
    }

    private var statusSection: some View {
        Section(.reachy("Robot")) {
            LabeledContent(.reachy("Name"), value: identity?.name ?? "—")
            LabeledContent(.reachy("Daemon"), value: identity?.daemonVersion ?? "—")
            LabeledContent(.reachy("Connection"), value: session.link.displayString)
            if let status = session.lastStatus {
                LabeledContent(
                    .reachy("Daemon state"),
                    value: String(localized: DaemonStateCaption.text(for: status.state))
                )
                // A `disabled` robot answers every motion command and stays limp,
                // so the motor mode belongs next to the daemon state.
                if let mode = status.backendStatus?.value1?.motorControlMode {
                    LabeledContent(.reachy("Motors"), value: mode.rawValue)
                }
            }
            HStack {
                Text(.reachy("Link"))
                Spacer()
                if case .unreachable = session.phase {
                    Label(.reachy("Unreachable — reconnecting…"), systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                } else if !session.isBackendRunning {
                    // Reachable but not drivable: claiming a green "Connected" here
                    // is what sent users looking for a network problem they don't have.
                    Label(.reachy("Backend stopped"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Label(.reachy("Connected"), systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            if let fault = session.backendFault {
                Label(fault, systemImage: "wrench.and.screwdriver")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
    }

    /// Power alone. The three destinations that used to sit above these buttons are
    /// each a tab or a settings row now — the controller behind Live, the move
    /// library at the root of its own tab, the daemon log with the rest of the
    /// diagnostics — so this screen is about the robot's identity and its state.
    private var controlSection: some View {
        Section(.reachy("Control")) {
            Button {
                Task { await session.wake() }
            } label: {
                Label(.reachy("Wake up"), systemImage: "sun.max")
            }
            .disabled(session.powerTransition != nil)
            Button {
                Task { await session.sleep() }
            } label: {
                Label(.reachy("Go to sleep"), systemImage: "moon.zzz")
            }
            .disabled(session.powerTransition != nil)
            if let transition = session.powerTransition {
                HStack {
                    ProgressView()
                    Text(transition.statusText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!isConnected)
    }

    private var isConnected: Bool {
        if case .connected = session.phase {
            return true
        }
        return false
    }
}
