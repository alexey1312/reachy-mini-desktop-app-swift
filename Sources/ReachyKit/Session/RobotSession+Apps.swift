import Foundation

/// The robot's app store, reached through the session so the UI never builds a
/// URL of its own.
public extension RobotSession {
    /// Every daemon serves `/api/apps/*` over the LAN, so unlike `canConfigureWiFi`
    /// this is not gated on a wireless robot. It is still a question worth asking:
    /// a remote session reaches the robot through a data channel that carries only
    /// part of this surface.
    var canManageApps: Bool {
        client is any RobotAppsClient
    }

    /// The whole catalogue, installed apps included — the daemon's own
    /// `list-available` without a source kind.
    func appCatalogue(refresh: Bool = false) async throws -> [RobotApp] {
        if !refresh, let cached = appCatalogueCache {
            return cached
        }
        let apps = try await withAppsClient { try await $0.availableApps() }
        appCatalogueCache = apps
        recordInstalled(apps.filter(\.isInstalled))
        return apps
    }

    func installedApps(refresh: Bool = false) async throws -> [RobotApp] {
        if !refresh, let cached = installedAppsCache {
            return cached
        }
        let apps = try await withAppsClient { try await $0.installedApps() }
        installedAppsCache = apps
        recordInstalled(apps)
        return apps
    }

    func currentApp() async throws -> RobotAppStatus? {
        let status = try await withAppsClient { try await $0.currentAppStatus() }
        recordRunning(status)
        return status
    }

    /// Refreshes the running-app reading for background observers. Unlike
    /// `currentApp()` it gates on the phase itself: a poll that outlives a
    /// disconnect must refuse rather than ride whatever client is still attached.
    func refreshCurrentApp() async throws {
        switch phase {
        case .connected, .unreachable: break
        case .idle, .connecting: throw ReachyKitError.notConnected
        }
        try assertSupportedDaemon()
        guard let client else { throw ReachyKitError.notConnected }
        guard let appsClient = client as? any RobotAppsClient else {
            throw ReachyKitError.appsUnavailable
        }
        let status = try await appsClient.currentAppStatus()
        recordRunning(status)
    }

    /// Refused with a 400 while another app holds the robot — stop that one first.
    func startApp(named name: String) async throws -> RobotAppStatus {
        let status = try await withAppsClient { try await $0.startApp(named: name) }
        recordRunning(status)
        return status
    }

    func restartCurrentApp() async throws -> RobotAppStatus {
        let status = try await withAppsClient { try await $0.restartCurrentApp() }
        recordRunning(status)
        return status
    }

    /// Refused with a 400 when nothing is running, which is what a second Stop
    /// looks like.
    func stopCurrentApp() async throws {
        try await withAppsClient { try await $0.stopCurrentApp() }
        recordRunning(nil)
    }

    /// All four return a job id; follow it with `appJobEvents(jobID:)`.
    ///
    /// The caches go at once rather than when the job ends: the robot's app list is
    /// in flux from this moment, and a stale list is what makes a screen offer
    /// "Install" for something it is already installing.
    func installApp(_ app: RobotApp) async throws -> String {
        try await startingJob { try await $0.installApp(app) }
    }

    func installPrivateSpace(id spaceID: String) async throws -> String {
        try await startingJob { try await $0.installPrivateSpace(id: spaceID) }
    }

    func removeApp(named name: String) async throws -> String {
        try await startingJob { try await $0.removeApp(named: name) }
    }

    func updateApp(named name: String) async throws -> String {
        try await startingJob { try await $0.updateApp(named: name) }
    }

    /// Follows one job to its end over the socket *and* the poll — see
    /// `AppJobMonitor` for why neither alone is enough.
    func appJobEvents(
        jobID: String,
        configuration: AppJobMonitor.Configuration = .install
    ) throws -> AsyncStream<AppJobMonitor.Event> {
        guard let address else { throw ReachyKitError.notConnected }
        guard let client = client as? any RobotAppsClient else { throw ReachyKitError.appsUnavailable }
        return AppJobMonitor(
            configuration: configuration,
            logs: {
                (try? JobLogStreamClient.appsManager(address: address, jobID: jobID).events())
                    ?? AsyncStream { $0.finish() }
            },
            job: { try await client.appJob(id: jobID) }
        ).events()
    }

    func appUpdates(force: Bool = false) async throws -> AppUpdatesSummary {
        try await withAppsClient { try await $0.appUpdates(force: force) }
    }

    func startupApp() async throws -> String? {
        try await withAppsClient { try await $0.startupApp() }
    }

    /// `nil` clears it. Refused with a 400 for an app that is not installed.
    @discardableResult
    func setStartupApp(_ name: String?) async throws -> String? {
        try await withAppsClient { try await $0.setStartupApp(name) }
    }

    /// Who is driving the robot — a local app, a Hugging Face relay session, or
    /// nobody.
    func appLockStatus() async throws -> RobotAppLockStatus {
        try await withAppsClient { try await $0.appLockStatus() }
    }

    /// Conversation App 1.0's semantic turn state over its direct LAN control
    /// socket. The app owns the port, so this works with daemon 1.9.0 even though
    /// relaying the same JSON-RPC frames over WebRTC requires a newer daemon.
    ///
    /// The app supplies the port and the session supplies the host — never the
    /// other way round, see ``RobotApp/customAppPort``.
    func conversationTurns(for app: RobotApp) throws -> AsyncStream<ConversationTurn> {
        guard let address else { throw ReachyKitError.notConnected }
        return try ConversationRPCClient(address: address, port: app.customAppPort).turns()
    }

    /// Where an app serves its **own** settings page, on the port it declared and
    /// the host this session is connected to.
    ///
    /// The daemon carries none of this: there is no route anywhere in the API for
    /// an app's own configuration, only `extra["custom_app_url"]` naming the port
    /// the app binds. So the settings a user is looking for are a page the app
    /// renders itself — the conversation app logs `Serving settings UI from
    /// …/static` as it comes up — and reaching them means dialling that port.
    ///
    /// The app supplies the port and the session supplies the host, never the
    /// other way round; see ``RobotApp/customAppPort``.
    ///
    /// Nil in three cases, all of them meaning "do not offer this":
    /// - the daemon reported no port. It scrapes that literal out of the app's
    ///   `main.py`, so its absence is the one signal available that an app serves
    ///   no page of its own. A link to a port nothing listens on is worse than no
    ///   link, which is why this does **not** fall back to 7860 the way
    ///   ``ConversationRPCClient`` does — that one is a background stream nobody
    ///   sees fail.
    /// - a remote session, which has no LAN address to dial. The page is served by
    ///   the app process on the robot's own network and the relay does not carry
    ///   it.
    /// - the app is not running. The process serving the page is the process that
    ///   died, so a crashed app takes its own settings down with it — including
    ///   the ones whose misconfiguration crashed it. Callers check the state; this
    ///   only knows about addresses.
    func appSettingsURL(for app: RobotApp) -> URL? {
        guard let address, let port = app.customAppPort else { return nil }
        return RobotAddress(host: address.host, port: port).httpURL(path: "/")
    }
}

/// What this session leaves behind for a widget that cannot ask the robot
/// anything itself.
///
/// Both writes ride calls the app was already making, so neither costs a round
/// trip — which is the whole reason they sit here rather than in the screen that
/// happens to trigger them, or in the three-second status poll, which learns
/// neither of these things.
private extension RobotSession {
    func recordInstalled(_ apps: [RobotApp]) {
        // An empty list is what a daemon mid-restart reports. Keep the last
        // identity-bound menu until a non-empty answer replaces it; otherwise a
        // transient restart disables every configured widget tile.
        guard !apps.isEmpty, let identity = connectedIdentity else { return }
        appsCache.write(apps.map(RobotAppSummary.init), robotID: identity.deduplicationKey)
    }

    func recordRunning(_ status: RobotAppStatus?) {
        runningApp = status
        // The snapshot keeps the two apart: a widget offering "Stop" for an app that
        // already died would be worse than one showing nothing, so only a live app
        // is named as running — and a dead one still travels, on its own field and
        // its own window, because a tile that quietly returns to idle explains
        // nothing at all.
        let running = status.flatMap { $0.isBusy ? $0 : nil }
        let identity = connectedIdentity
        snapshots.recordRunningApp(
            title: running?.app.title,
            name: running?.app.name,
            failed: status.flatMap(Self.failure),
            robotID: identity?.deduplicationKey,
            robotName: identity?.name,
            isAwake: isAwake
        )
    }

    /// A finished app is not a failure: `done` is what an app that ran to
    /// completion reports, and the dock leaves as quietly as the widget should.
    static func failure(in status: RobotAppStatus) -> RobotSnapshot.FailedApp? {
        guard status.state == .error else { return nil }
        return RobotSnapshot.FailedApp(
            name: status.app.name,
            title: status.app.title,
            error: status.error
        )
    }

    var connectedIdentity: RobotIdentity? {
        switch phase {
        case let .connected(identity), let .unreachable(identity): identity
        case .idle, .connecting: nil
        }
    }
}

extension RobotSession {
    func withAppsClient<T>(_ call: (any RobotAppsClient) async throws -> T) async throws -> T {
        guard let client else { throw ReachyKitError.notConnected }
        guard let appsClient = client as? any RobotAppsClient else {
            throw ReachyKitError.appsUnavailable
        }
        return try await call(appsClient)
    }

    private func startingJob(_ call: (any RobotAppsClient) async throws -> String) async throws -> String {
        let jobID = try await withAppsClient(call)
        appCatalogueCache = nil
        installedAppsCache = nil
        return jobID
    }
}
