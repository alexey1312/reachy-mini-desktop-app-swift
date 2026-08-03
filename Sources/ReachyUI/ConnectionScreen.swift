import ReachyKit
import SwiftUI

/// Discovery list + manual address entry. Manual entry is a first-class flow,
/// not a fallback (upstream issue #269).
struct ConnectionScreen: View {
    let session: RobotSession

    @State private var browser = RobotBrowser()
    @State private var manualInput = KnownRobots.lastAddress.map(\.displayString) ?? ""
    @State private var resolving: String?
    @State private var resolvedServiceIDs: Set<String> = []
    @State private var pendingCandidates: [RobotAddress] = []
    @State private var attemptedCandidates: Set<RobotAddress> = []
    @State private var autoConnectTask: Task<Void, Never>?

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
        .onAppear {
            browser.start()
            enqueueInitialCandidates()
        }
        .onChange(of: browser.services) { _, services in
            resolveDiscoveredServices(services)
        }
        .onDisappear {
            autoConnectTask?.cancel()
            autoConnectTask = nil
            browser.stop()
        }
    }

    private var discoverySection: some View {
        Section("Robots on this network") {
            if !session.automaticConnectionAllowed {
                Label("Automatic reconnect paused", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }
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
                connectManually(to: address)
            }
            .disabled(RobotAddress(parsing: manualInput) == nil)
            if KnownRobots.lastAddress != nil {
                Button("Forget last robot", role: .destructive) {
                    KnownRobots.lastAddress = nil
                    manualInput = ""
                }
            }
        }
    }

    /// Tries known/static candidates first; Bonjour results are appended as they resolve.
    private func enqueueInitialCandidates() {
        guard session.automaticConnectionAllowed else { return }
        var candidates = [
            RobotAddress(host: "reachy-mini.local"),
            RobotAddress(host: "reachy-mini.home"),
        ]
        #if os(macOS)
            // The simulator runs on this Mac and may not advertise Bonjour.
            candidates.insert(RobotAddress(host: "127.0.0.1"), at: 0)
        #endif
        if let last = KnownRobots.lastAddress {
            candidates.insert(last, at: 0)
        }
        enqueue(candidates)
    }

    private func resolveDiscoveredServices(_ services: [RobotBrowser.DiscoveredService]) {
        guard session.automaticConnectionAllowed else { return }
        for service in services where !resolvedServiceIDs.contains(service.id) {
            resolvedServiceIDs.insert(service.id)
            Task { @MainActor in
                if let address = await BonjourResolver.resolve(service.endpoint) {
                    enqueue([address])
                }
            }
        }
    }

    private func enqueue(_ candidates: [RobotAddress]) {
        for candidate in candidates
            where !attemptedCandidates.contains(candidate) && !pendingCandidates.contains(candidate)
        {
            pendingCandidates.append(candidate)
        }
        startAutoConnectIfNeeded()
    }

    private func startAutoConnectIfNeeded() {
        guard autoConnectTask == nil,
              session.automaticConnectionAllowed,
              session.phase == .idle,
              !pendingCandidates.isEmpty
        else { return }

        autoConnectTask = Task { @MainActor in
            defer { autoConnectTask = nil }
            while !Task.isCancelled,
                  session.automaticConnectionAllowed,
                  session.phase == .idle,
                  !pendingCandidates.isEmpty
            {
                let candidate = pendingCandidates.removeFirst()
                attemptedCandidates.insert(candidate)
                if await session.connect(to: candidate, automatically: true) {
                    return
                }
            }
        }
    }

    private func connectManually(to address: RobotAddress) {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        Task { await session.connect(to: address) }
    }

    private func connect(to service: RobotBrowser.DiscoveredService) {
        autoConnectTask?.cancel()
        autoConnectTask = nil
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
