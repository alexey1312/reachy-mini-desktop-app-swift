import ReachyKit
import SwiftUI

/// Discovery list + manual address entry. Manual entry is a first-class flow,
/// not a fallback (upstream issue #269).
struct ConnectionScreen: View {
    let session: RobotSession

    @State private var browser = RobotBrowser()
    @State private var manualInput = KnownRobots.lastAddress.map(\.displayString) ?? ""
    @State private var resolving: String?

    var body: some View {
        Form {
            discoverySection
            manualSection
            if let error = session.lastError {
                Section {
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(session.phase == .connecting)
        .overlay {
            if session.phase == .connecting {
                ProgressView("Connecting…")
            }
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    private var discoverySection: some View {
        Section("Robots on this network") {
            if browser.permissionLooksDenied {
                Label("Local Network permission denied", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                #if os(iOS)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                #endif
            }
            if browser.services.isEmpty {
                Text("Searching…").foregroundStyle(.secondary)
            }
            ForEach(browser.services) { service in
                Button {
                    connect(to: service)
                } label: {
                    LabeledContent(service.name) {
                        if resolving == service.id {
                            ProgressView()
                        } else {
                            Text(service.type).font(.caption.monospaced())
                        }
                    }
                }
            }
        }
    }

    private var manualSection: some View {
        Section("Manual address") {
            TextField("host, host:port, or IP", text: $manualInput)
                .autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            #endif
            Button("Connect") {
                guard let address = RobotAddress(parsing: manualInput) else { return }
                Task { await session.connect(to: address) }
            }
            .disabled(RobotAddress(parsing: manualInput) == nil)
        }
    }

    private func connect(to service: RobotBrowser.DiscoveredService) {
        resolving = service.id
        Task {
            defer { resolving = nil }
            guard let address = await BonjourResolver.resolve(service.endpoint) else { return }
            await session.connect(to: address)
        }
    }
}

extension RobotAddress {
    var displayString: String {
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return port == Self.defaultPort ? hostPart : "\(hostPart):\(port)"
    }
}
