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
    @State private var rescanTask: Task<Void, Never>?

    /// Upstream's `INTERVALS.DISCOVERY_SCAN`.
    private let rescanInterval: Duration = .seconds(10)

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
            startPeriodicRescan()
        }
        .onChange(of: browser.services) { _, services in
            resolveDiscoveredServices(services)
        }
        .onDisappear {
            autoConnectTask?.cancel()
            autoConnectTask = nil
            rescanTask?.cancel()
            rescanTask = nil
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Searching…")
                    Text(
                        "Known addresses are retried every 10 s. A robot whose daemon isn't running "
                            + "answers nothing on the network — power it on, or enter its address below."
                    )
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
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
            Label(
                "The daemon uses unencrypted HTTP without authentication. Connect only on a trusted private network.",
                systemImage: "lock.open.trianglebadge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(.orange)
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
        // Upstream also probes `reachy-mini.home`, which cannot work here: App
        // Transport Security exempts `.local`, link-local and single-label names
        // from its HTTPS requirement, and a qualified `.home` name is none of
        // those. Probing it only ever produced a -1022 error on screen.
        var candidates = [RobotAddress(host: "reachy-mini.local")]
        #if os(macOS) || targetEnvironment(simulator)
            // A simulated daemon runs on this Mac and advertises no Bonjour the
            // simulator can see; loopback reaches the host either way.
            candidates.insert(RobotAddress(host: "127.0.0.1"), at: 0)
        #endif
        if let last = KnownRobots.lastAddress {
            candidates.insert(last, at: 0)
        }
        enqueue(candidates)
    }

    /// A robot powered on after this screen appeared advertises nothing our
    /// browser can react to when mDNS doesn't reach us, so the known addresses
    /// have to be retried instead of being written off after one failed pass.
    private func startPeriodicRescan() {
        rescanTask?.cancel()
        rescanTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: rescanInterval)
                guard !Task.isCancelled, session.phase == .idle else { continue }
                attemptedCandidates = []
                enqueueInitialCandidates()
            }
        }
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
