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
            }
            Button {
                Task { await session.wake() }
            } label: {
                Label("Wake up", systemImage: "sun.max")
            }
            Button {
                Task { await session.sleep() }
            } label: {
                Label("Go to sleep", systemImage: "moon.zzz")
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
