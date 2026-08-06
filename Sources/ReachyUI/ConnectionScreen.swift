import ReachyDesign
import ReachyKit
import SwiftUI

/// Discovery list + manual address entry. Manual entry is a first-class flow,
/// not a fallback (upstream issue #269).
struct ConnectionScreen: View {
    let session: RobotSession
    /// Absent in previews and wherever the remote list has nowhere to be
    /// presented from, which is what hides the section rather than a flag.
    var showRemoteRobots: (() -> Void)?

    @State private var browser: RobotBrowser
    @State private var manualInput: String
    @Environment(\.reachyPreviewMode) private var previewMode
    @State private var resolving: String?
    @State private var resolvedServiceIDs: Set<String> = []
    @State private var pendingCandidates: [RobotAddress] = []
    @State private var attemptedCandidates: Set<RobotAddress> = []
    @State private var autoConnectTask: Task<Void, Never>?
    @State private var rescanTask: Task<Void, Never>?
    @State private var showsOnboarding = false
    @State private var awaitedHardwareID = KnownRobots.pendingProvisionedHardwareID
    /// Resolved in `onAppear` rather than defaulted here: a default argument is evaluated in a
    /// nonisolated context, and this model is main-actor isolated.
    @State private var knownRobots: KnownRobotsModel?

    /// Upstream's `INTERVALS.DISCOVERY_SCAN`.
    private let rescanInterval: Duration = .seconds(10)

    init(
        session: RobotSession,
        browser: RobotBrowser = RobotBrowser(),
        manualInput: String? = nil,
        knownRobots: KnownRobotsModel? = nil,
        showRemoteRobots: (() -> Void)? = nil
    ) {
        self.session = session
        self.showRemoteRobots = showRemoteRobots
        _browser = State(initialValue: browser)
        _manualInput = State(initialValue: manualInput ?? KnownRobots.lastAddress.map(\.displayString) ?? "")
        _knownRobots = State(initialValue: knownRobots)
    }

    var body: some View {
        Group {
            if case let .connecting(.needsDaemonUpdate(_, requirement)) = session.phase {
                // Its own screen rather than a stepper row: retrying is pointless
                // here, and everything the user can do is an update decision.
                NavigationStack {
                    DaemonUpdateScreen(session: session, requirement: requirement)
                }
            } else if needsDecision {
                // Start / continue / cancel: the discovery list underneath would
                // only compete with a choice the user has to make.
                Form {
                    ConnectionStepper(session: session)
                }
                .formStyle(.grouped)
            } else {
                Form {
                    ConnectOrientation()
                    if isProbing {
                        ConnectionStepper(session: session)
                    }
                    // Disabled section by section rather than on the whole form:
                    // `disabled` is cumulative and a child cannot re-enable itself, which
                    // would take the Bluetooth setup button down with everything else —
                    // and the sweep it is waiting on runs every 10 s forever when nothing
                    // answers, which is exactly when that button is the way out.
                    discoverySection
                        .disabled(isProbing)
                    YourReachiesSection(show: showRemoteRobots)
                    setUpSection
                    manualSection
                        .disabled(isProbing)
                    if let error = session.lastError {
                        Section {
                            Text(error)
                                .font(.caption.monospaced())
                                .foregroundStyle(.red)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .onAppear {
            guard !previewMode else { return }
            let model = knownRobots ?? KnownRobotsModel()
            knownRobots = model
            model.start()
            browser.start()
            enqueueInitialCandidates()
            startPeriodicRescan()
            // Only the very first launch, and never as a gate: a robot already on the
            // network is found without any of this, and the button below reopens it.
            if KnownRobots.lastAddress == nil, !KnownRobots.hasCompletedOnboarding {
                showsOnboarding = true
            }
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingFlow(onFinish: finishOnboarding) { showsOnboarding = false }
        }
        .onChange(of: browser.services) { _, services in
            knownRobots?.updateDiscovered(Set(services.compactMap(\.hardwareID)))
            resolveDiscoveredServices(services)
        }
        .onDisappear {
            autoConnectTask?.cancel()
            autoConnectTask = nil
            rescanTask?.cancel()
            rescanTask = nil
            browser.stop()
            knownRobots?.stop()
        }
    }

    /// An attempt is in flight and will resolve itself. Shown inline so the
    /// discovery list stays put while the candidate sweep walks its addresses.
    private var isProbing: Bool {
        switch session.phase {
        case .connecting(.handshaking), .connecting(.checkingBackend): true
        default: false
        }
    }

    /// The attempt stopped and needs the user.
    private var needsDecision: Bool {
        switch session.phase {
        case .connecting(.backendUnavailable), .connecting(.failed): true
        default: false
        }
    }

    private var discoverySection: some View {
        Section {
            if !session.automaticConnectionAllowed {
                Label(.reachy("Automatic reconnect paused"), systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }
            if browser.permissionLooksDenied {
                Label(.reachy("Local Network permission denied"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                #if os(iOS)
                    Button(.reachy("Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                #endif
            }
            if isSearching {
                Text(.reachy("Searching…"))
                    .foregroundStyle(Tone.quiet.style)
            }
            // Robots that answered a handshake before are listed whether or not Bonjour finds
            // them: mDNS does not reach every network, and an absent robot is worth showing as
            // absent rather than not at all.
            ForEach(knownEntries) { entry in
                Button {
                    connectManually(to: entry.robot.address)
                } label: {
                    LabeledContent(entry.robot.name ?? entry.robot.address.displayString) {
                        KnownRobotStatusLabel(status: entry.status)
                    }
                }
                .swipeActions {
                    Button(.reachy("Forget"), role: .destructive) {
                        knownRobots?.forget(entry.id)
                    }
                }
            }
            ForEach(undiscoveredServices) { service in
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
        } header: {
            Text(.reachy("Robots on this network"))
        } footer: {
            // Under the group rather than inside the card, which is how every other
            // explanation on this screen is placed. Only while the list is empty:
            // once a robot is listed this says nothing the list does not.
            if isSearching {
                Text(
                    .reachy(
                        // swiftlint:disable:next line_length
                        "Known addresses are retried every 10 s. A robot whose daemon isn't running answers nothing on the network — power it on, or enter its address below."
                    )
                )
            }
        }
    }

    /// Nothing found yet, from either source. The one state this screen spends
    /// most of its life in, and the only one the explanation below is about.
    private var isSearching: Bool {
        knownEntries.isEmpty && undiscoveredServices.isEmpty
    }

    private var knownEntries: [KnownRobotsModel.Entry] {
        knownRobots?.entries ?? []
    }

    /// A robot already listed from storage must not appear twice. The advert's TXT `unit_id` is
    /// the same string the handshake stored, so the two are matched on identity, not address
    /// (rule 4). An advert without one — the legacy `_http._tcp` type — is always shown.
    private var undiscoveredServices: [RobotBrowser.DiscoveredService] {
        let known = Set(knownEntries.map(\.id))
        return browser.services.filter { service in
            service.hardwareID.map { !known.contains($0) } ?? true
        }
    }

    /// Its own section so the sweep cannot switch it off. Bluetooth setup has nothing to
    /// do with an HTTP handshake being in flight, and a robot that has never been on a
    /// network is precisely the one that keeps that handshake failing.
    private var setUpSection: some View {
        Section {
            if let awaitedHardwareID {
                Label(
                    .reachy(
                        // swiftlint:disable:next line_length
                        "Waiting for the robot you just set up (\(awaitedHardwareID)). If this phone is still on reachy-mini-ap, switch it back to your home Wi-Fi."
                    ),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button(.reachy("Set up a new robot over Bluetooth")) {
                showsOnboarding = true
            }
        }
    }

    /// The robot reported where it landed over Bluetooth, which beats waiting for the
    /// sweep to stumble across it. The hardware id is what confirms the arrival, and
    /// `RobotSession` clears it on the handshake.
    private func finishOnboarding(_ outcome: OnboardingOutcome) {
        showsOnboarding = false
        awaitedHardwareID = outcome.hardwareID
        guard let address = outcome.address else { return }
        attemptedCandidates.remove(address)
        enqueue([address])
    }

    private var manualSection: some View {
        Section(.reachy("Manual address")) {
            Label(
                .reachy(
                    // swiftlint:disable:next line_length
                    "The daemon uses unencrypted HTTP without authentication. Connect only on a trusted private network."
                ),
                systemImage: "lock.open.trianglebadge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            TextField(.reachy("host, host:port, or IP"), text: $manualInput)
                .autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            #endif
            Button(.reachy("Connect")) {
                guard let address = RobotAddress(parsing: manualInput) else { return }
                connectManually(to: address)
            }
            .disabled(RobotAddress(parsing: manualInput) == nil)
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
