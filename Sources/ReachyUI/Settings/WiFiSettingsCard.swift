import ReachyKit
import SwiftUI

/// What the robot is on, what it remembers, and why the last attempt failed.
///
/// Read-only apart from forgetting: joining a network is the provisioning flow's job, and
/// it works over Bluetooth as well, which is the case that actually needs it.
struct WiFiSettingsCard: View {
    let session: RobotSession

    @State private var status: WiFiStatus?
    @State private var joinError: String?
    @State private var loadFailure: String?
    @State private var busy = false
    @Environment(\.reachyPreviewMode) private var previewMode

    init(session: RobotSession, status: WiFiStatus? = nil, joinError: String? = nil, loadFailure: String? = nil) {
        self.session = session
        _status = State(initialValue: status)
        _joinError = State(initialValue: joinError)
        _loadFailure = State(initialValue: loadFailure)
    }

    var body: some View {
        Section {
            LabeledContent("Mode", value: modeText)
            if let connected = status?.connected {
                LabeledContent("Network", value: connected)
            }
            if let joinError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(joinError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button("Clear this error") {
                        Task { await clearError() }
                    }
                    .buttonStyle(.borderless)
                }
            }
            ForEach(status?.known ?? [], id: \.self) { network in
                LabeledContent(network) {
                    Button("Forget", role: .destructive) {
                        Task { await forget(network) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(busy)
                }
            }
            if let loadFailure {
                Text(loadFailure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Network")
        } footer: {
            Text("Forgetting the network the robot is on takes it off this network at the next restart. "
                + "The robot's own hotspot cannot be forgotten.")
        }
        .task {
            guard !previewMode else { return }
            await load()
        }
    }

    private var modeText: String {
        switch status?.mode {
        case .wlan: "On a network"
        case .hotspot: "Its own hotspot"
        case .disconnected: "Not connected"
        case .busy: "Working…"
        case nil: status == nil ? "—" : "Unknown"
        }
    }

    private func load() async {
        do {
            status = try await session.wifiStatus()
            joinError = try await session.lastWiFiError()
            loadFailure = nil
        } catch {
            loadFailure = describe(error)
        }
    }

    private func forget(_ ssid: String) async {
        busy = true
        defer { busy = false }
        do {
            try await session.forgetWiFi(ssid: ssid)
            await load()
        } catch {
            loadFailure = describe(error)
        }
    }

    private func clearError() async {
        do {
            try await session.resetWiFiError()
            joinError = nil
        } catch {
            loadFailure = describe(error)
        }
    }

    private func describe(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
