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
            if let address = session.address {
                NavigationLink {
                    ControllerScreen(session: session, address: address)
                } label: {
                    Label("Controller", systemImage: "gamecontroller")
                }
                NavigationLink {
                    MovesScreen(session: session)
                } label: {
                    Label("Moves & expressions", systemImage: "music.note")
                }
                NavigationLink {
                    RobotViewerScreen(address: address)
                } label: {
                    Label("3D model", systemImage: "cube.transparent")
                }
                // Read-only, so it needs no motors — but the geometry and state
                // routes are both behind the backend.
                .disabled(!session.isBackendRunning)
                NavigationLink {
                    LogConsoleScreen(address: address)
                } label: {
                    Label("Daemon logs", systemImage: "terminal")
                }
                if hasCamera {
                    NavigationLink {
                        CameraScreen(address: address)
                    } label: {
                        Label("Camera", systemImage: "video")
                    }
                    // Video needs no motors — an asleep robot still streams — but
                    // `daemon.stop()` tears the media server down with the backend.
                    .disabled(!session.isBackendRunning)
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

    private var hasCamera: Bool {
        session.lastStatus?.wirelessVersion == true || session.lastStatus?.simulationEnabled == true
    }

    private var isConnected: Bool {
        if case .connected = session.phase {
            return true
        }
        return false
    }
}
