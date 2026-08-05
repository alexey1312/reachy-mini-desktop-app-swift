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
                Button("Disconnect", role: .destructive) {
                    session.disconnect()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(identity?.name ?? "Robot")
        .toolbar {
            ToolbarItem {
                NavigationLink {
                    SettingsScreen(session: session)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    private var identity: RobotIdentity? {
        switch session.phase {
        case let .connected(identity), let .unreachable(identity): identity
        default: nil
        }
    }

    private var statusSection: some View {
        Section("Robot") {
            LabeledContent("Name", value: identity?.name ?? "—")
            LabeledContent("Daemon", value: identity?.daemonVersion ?? "—")
            LabeledContent("Connection", value: session.link.displayString)
            if let status = session.lastStatus {
                LabeledContent("Daemon state", value: String(describing: status.state))
                // A `disabled` robot answers every motion command and stays limp,
                // so the motor mode belongs next to the daemon state.
                if let mode = status.backendStatus?.value1?.motorControlMode {
                    LabeledContent("Motors", value: mode.rawValue)
                }
            }
            HStack {
                Text("Link")
                Spacer()
                if case .unreachable = session.phase {
                    Label("Unreachable — reconnecting…", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                } else if !session.isBackendRunning {
                    // Reachable but not drivable: claiming a green "Connected" here
                    // is what sent users looking for a network problem they don't have.
                    Label("Backend stopped", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Label("Connected", systemImage: "checkmark.circle")
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

    private var controlSection: some View {
        Section("Control") {
            // Three separate questions, where one `if let address` used to stand
            // for all of them. Only the middle one is genuinely LAN-only.
            if session.canTeleoperate {
                NavigationLink {
                    ControllerScreen(session: session)
                } label: {
                    Label("Controller", systemImage: "gamecontroller")
                }
            }
            if session.canPlayMoves {
                NavigationLink {
                    MovesScreen(session: session)
                } label: {
                    Label("Moves & expressions", systemImage: "music.note")
                }
            }
            if session.canReadDaemonLogs {
                NavigationLink {
                    LogConsoleScreen(session: session)
                } label: {
                    Label("Daemon logs", systemImage: "terminal")
                }
            }
            Button {
                Task { await session.wake() }
            } label: {
                Label("Wake up", systemImage: "sun.max")
            }
            .disabled(session.powerTransition != nil)
            Button {
                Task { await session.sleep() }
            } label: {
                Label("Go to sleep", systemImage: "moon.zzz")
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
