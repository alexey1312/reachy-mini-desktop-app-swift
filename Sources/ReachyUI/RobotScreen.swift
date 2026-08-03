import ReachyKit
import SwiftUI

/// Connected-robot screen: identity, live daemon status, wake/sleep.
struct RobotScreen: View {
    let session: RobotSession

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
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
            LabeledContent("Address", value: session.address?.displayString ?? "—")
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
                } else {
                    Label("Connected", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var controlSection: some View {
        Section("Control") {
            if let address = session.address {
                NavigationLink {
                    ControllerScreen(address: address)
                } label: {
                    Label("Controller", systemImage: "gamecontroller")
                }
                NavigationLink {
                    MovesScreen(session: session)
                } label: {
                    Label("Moves & expressions", systemImage: "music.note")
                }
                NavigationLink {
                    LogConsoleScreen(address: address)
                } label: {
                    Label("Daemon logs", systemImage: "terminal")
                }
                if session.lastStatus?.wirelessVersion == true || session.lastStatus?.simulationEnabled == true {
                    NavigationLink {
                        CameraScreen(address: address)
                    } label: {
                        Label("Camera", systemImage: "video")
                    }
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
                    Text(Self.description(of: transition))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!isConnected)
    }

    /// Starting a cold backend can take up to 90 s — silence would read as a hang.
    private static func description(of transition: RobotSession.PowerTransition) -> String {
        switch transition {
        case .startingBackend: "Starting the robot backend… this can take a minute"
        case .wakingUp: "Waking up…"
        case .goingToSleep: "Going to sleep…"
        }
    }

    private var isConnected: Bool {
        if case .connected = session.phase {
            return true
        }
        return false
    }
}
