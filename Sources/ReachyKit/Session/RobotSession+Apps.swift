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
        return apps
    }

    func installedApps(refresh: Bool = false) async throws -> [RobotApp] {
        if !refresh, let cached = installedAppsCache {
            return cached
        }
        let apps = try await withAppsClient { try await $0.installedApps() }
        installedAppsCache = apps
        return apps
    }

    func currentApp() async throws -> RobotAppStatus? {
        try await withAppsClient { try await $0.currentAppStatus() }
    }

    /// Refused with a 400 while another app holds the robot — stop that one first.
    func startApp(named name: String) async throws -> RobotAppStatus {
        try await withAppsClient { try await $0.startApp(named: name) }
    }

    func restartCurrentApp() async throws -> RobotAppStatus {
        try await withAppsClient { try await $0.restartCurrentApp() }
    }

    /// Refused with a 400 when nothing is running, which is what a second Stop
    /// looks like.
    func stopCurrentApp() async throws {
        try await withAppsClient { try await $0.stopCurrentApp() }
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
}

extension RobotSession {
    func withAppsClient<T>(_ call: (any RobotAppsClient) async throws -> T) async throws -> T {
        guard let client else { throw ReachyKitError.notConnected }
        guard let appsClient = client as? any RobotAppsClient else {
            throw ReachyKitError.appsUnavailable
        }
        do {
            let result = try await call(appsClient)
            lastError = nil
            return result
        } catch {
            lastError = Self.describe(error)
            throw error
        }
    }

    private func startingJob(_ call: (any RobotAppsClient) async throws -> String) async throws -> String {
        let jobID = try await withAppsClient(call)
        appCatalogueCache = nil
        installedAppsCache = nil
        return jobID
    }
}
