import Foundation
@testable import ReachyKit
import Testing

/// A daemon that can serve apps. `RobotAPIClient` is what `connect` needs;
/// `RobotAppsClient` is the capability the session gates the store on.
private final class AppsRobotClient: RobotAPIClient, RobotAppsClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var catalogueCalls = 0
    private(set) var installedCalls = 0
    private(set) var removed: [String] = []
    private(set) var running: RobotAppStatus?
    var failsCatalogue = false
    var returnsEmptyInstalled = false

    private var status: Components.Schemas.DaemonStatus {
        let json = """
        {"robot_name":"testbot","state":"running","wireless_version":true,
         "desktop_app_daemon":false,"simulation_enabled":true,"mockup_sim_enabled":false,
         "backend_status":{"motor_control_mode":"enabled","error":null}}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Components.Schemas.DaemonStatus.self, from: Data(json.utf8))
    }

    func handshake() async throws -> RobotConnection.Handshake {
        .init(identity: .init(hardwareID: "hw", name: "testbot", daemonVersion: "1.9.0"), status: status)
    }

    func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        status
    }

    func wakeUp() async throws -> String {
        "wake"
    }

    func gotoSleep() async throws -> String {
        "sleep"
    }

    func availableApps() async throws -> [RobotApp] {
        lock.withLock { catalogueCalls += 1 }
        if failsCatalogue {
            throw ReachyKitError.daemonRejected(statusCode: 503)
        }
        return [
            Self.app(name: "reachy-mini-dance", kind: "hf_space"),
            Self.app(name: "dance_party", kind: "installed"),
        ]
    }

    func installedApps() async throws -> [RobotApp] {
        lock.withLock { installedCalls += 1 }
        if returnsEmptyInstalled {
            return []
        }
        return [Self.app(name: "dance_party", kind: "installed")]
    }

    func removeApp(named name: String) async throws -> String {
        lock.withLock { removed.append(name) }
        return "job-1"
    }

    func currentAppStatus() async throws -> RobotAppStatus? {
        lock.withLock { running }
    }

    func startApp(named name: String) async throws -> RobotAppStatus {
        let status = Self.status(name: name)
        lock.withLock { running = status }
        return status
    }

    func stopCurrentApp() async throws {
        lock.withLock { running = nil }
    }

    func setRunning(_ status: RobotAppStatus?) {
        lock.withLock { running = status }
    }

    static func status(name: String, state: String = "running") -> RobotAppStatus {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(RobotAppStatus.self, from: Data(#"""
        {"info": {"name": "\#(name)", "source_kind": "installed", "extra": {}}, "state": "\#(state)"}
        """#.utf8))
    }

    static func app(name: String, kind: String) -> RobotApp {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(RobotApp.self, from: Data(#"""
        {"name": "\#(name)", "source_kind": "\#(kind)", "extra": {}}
        """#.utf8))
    }
}

/// A daemon with no app surface at all — the shape every other capability test
/// uses to prove a screen can ask before it calls.
private final class PlainRobotClient: RobotAPIClient, @unchecked Sendable {
    private var status: Components.Schemas.DaemonStatus {
        let json = """
        {"robot_name":"testbot","state":"running","wireless_version":false,
         "desktop_app_daemon":false,"simulation_enabled":true,"mockup_sim_enabled":false,
         "backend_status":{"motor_control_mode":"enabled","error":null}}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Components.Schemas.DaemonStatus.self, from: Data(json.utf8))
    }

    func handshake() async throws -> RobotConnection.Handshake {
        .init(identity: .init(hardwareID: "hw", name: "testbot", daemonVersion: "1.9.0"), status: status)
    }

    func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        status
    }

    func wakeUp() async throws -> String {
        "wake"
    }

    func gotoSleep() async throws -> String {
        "sleep"
    }
}

@MainActor
@Suite("Robot session apps", .timeLimit(.minutes(1)))
struct RobotSessionAppsTests {
    /// What the session leaves behind for the widget. One table per test:
    /// `--parallel` runs suites concurrently against a single shared one.
    private struct Stores {
        let snapshots: RobotSnapshotStore
        let apps: RobotAppsCacheStore

        init(defaults: UserDefaults) {
            snapshots = RobotSnapshotStore(defaults: defaults)
            apps = RobotAppsCacheStore(defaults: defaults)
        }
    }

    private func makeStores() throws -> Stores {
        try Stores(defaults: #require(UserDefaults(suiteName: "RobotSessionAppsTests.\(UUID().uuidString)")))
    }

    private func connected(_ client: any RobotAPIClient, stores: Stores? = nil) async throws -> RobotSession {
        let stores = try stores ?? makeStores()
        let session = RobotSession(snapshots: stores.snapshots, appsCache: stores.apps) { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        return session
    }

    @Test("the store is out of reach until a robot is connected")
    func requiresAConnection() async {
        let session = RobotSession { _ in AppsRobotClient() }
        #expect(session.canManageApps == false)

        _ = await session.connect(to: .init(host: "127.0.0.1"))
        #expect(session.canManageApps)
    }

    /// Unlike `/wifi/*` and `/update/*`, `/api/apps/*` is on every daemon — but a
    /// remote session reaches the robot over a data channel that carries only part
    /// of it, so the capability still has to be asked for rather than assumed.
    @Test("a daemon with no app surface says so instead of failing later")
    func reportsMissingCapability() async throws {
        let session = try await connected(PlainRobotClient())

        #expect(session.canManageApps == false)
        await #expect(throws: ReachyKitError.appsUnavailable) {
            try await session.appCatalogue()
        }
    }

    /// The catalogue is a Hugging Face round trip on the robot's side; re-fetching
    /// it every time a screen appears would make the store feel broken.
    @Test("the catalogue is fetched once and reused")
    func cachesTheCatalogue() async throws {
        let client = AppsRobotClient()
        let session = try await connected(client)

        _ = try await session.appCatalogue()
        _ = try await session.appCatalogue()
        #expect(client.catalogueCalls == 1)

        _ = try await session.appCatalogue(refresh: true)
        #expect(client.catalogueCalls == 2)
    }

    @Test("removing an app makes the installed list stale at once")
    func removalInvalidatesTheInstalledList() async throws {
        let client = AppsRobotClient()
        let session = try await connected(client)

        _ = try await session.installedApps()
        _ = try await session.installedApps()
        #expect(client.installedCalls == 1)

        _ = try await session.removeApp(named: "dance_party")
        _ = try await session.installedApps()

        #expect(client.removed == ["dance_party"])
        #expect(client.installedCalls == 2)
    }

    @Test("a daemon that refuses leaves its reason on the session")
    func reportsFailures() async throws {
        let client = AppsRobotClient()
        client.failsCatalogue = true
        let session = try await connected(client)

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 503)) {
            try await session.appCatalogue()
        }
        #expect(session.lastError?.isEmpty == false)
    }

    /// Caches are per connection: the next robot has its own apps, and showing it
    /// the previous one's list would be worse than a spinner.
    @Test("disconnecting forgets what was cached")
    func forgetsCacheOnDisconnect() async throws {
        let client = AppsRobotClient()
        let session = try await connected(client)

        _ = try await session.appCatalogue()
        session.disconnect()
        _ = await session.connect(to: .init(host: "127.0.0.1"))
        _ = try await session.appCatalogue()

        #expect(client.catalogueCalls == 2)
    }

    // MARK: - What the widget reads

    /// The widget offers a menu of apps it cannot ask for, so the catalogue call
    /// leaves one behind. Only the installed half: the rest is not launchable.
    @Test("listing the catalogue leaves the installed apps where a widget can read them")
    func cachesInstalledAppsForTheWidget() async throws {
        let stores = try makeStores()
        let session = try await connected(AppsRobotClient(), stores: stores)

        _ = try await session.appCatalogue()

        #expect(stores.apps.current(for: "hw")?.installed.map(\.name) == ["dance_party"])
    }

    @Test("listing the installed apps leaves the same menu behind")
    func cachesInstalledAppsFromTheInstalledList() async throws {
        let stores = try makeStores()
        let session = try await connected(AppsRobotClient(), stores: stores)

        _ = try await session.installedApps()

        #expect(stores.apps.current(for: "hw")?.installed.map(\.name) == ["dance_party"])
    }

    @Test("starting an app names it in the snapshot, and stopping clears it")
    func recordsTheRunningApp() async throws {
        let stores = try makeStores()
        let session = try await connected(AppsRobotClient(), stores: stores)

        _ = try await session.startApp(named: "dance_party")
        #expect(stores.snapshots.current?.runningAppName == "dance_party")

        try await session.stopCurrentApp()
        #expect(stores.snapshots.current?.runningAppName == nil)
    }

    @Test("asking what is running records the answer")
    func recordsTheAnswerToCurrentApp() async throws {
        let stores = try makeStores()
        let client = AppsRobotClient()
        let session = try await connected(client, stores: stores)
        _ = try await client.startApp(named: "dance_party")

        _ = try await session.currentApp()

        #expect(stores.snapshots.current?.runningAppName == "dance_party")
    }

    @Test("a terminal current-app status clears the running app")
    func clearsTerminalCurrentAppStatuses() async throws {
        let stores = try makeStores()
        let client = AppsRobotClient()
        let session = try await connected(client, stores: stores)
        _ = try await session.startApp(named: "dance_party")
        client.setRunning(AppsRobotClient.status(name: "dance_party", state: "done"))

        _ = try await session.currentApp()

        #expect(stores.snapshots.current?.runningAppName == nil)
        #expect(stores.snapshots.current?.runningAppTakenAt == nil)
    }

    // MARK: - What the dock reads

    /// The same funnel feeds two readers with deliberately different appetites, so
    /// every command has to be checked against both.
    @Test("every app command leaves the session's own reading up to date")
    func recordsTheRunningAppOnTheSession() async throws {
        let client = AppsRobotClient()
        let session = try await connected(client)
        #expect(session.runningApp == nil)

        _ = try await session.startApp(named: "dance_party")
        #expect(session.runningApp?.app.name == "dance_party")

        try await session.stopCurrentApp()
        #expect(session.runningApp == nil)

        _ = try await client.startApp(named: "dance_party")
        _ = try await session.currentApp()
        #expect(session.runningApp?.app.name == "dance_party")
    }

    /// The divergence between the two readers, and the reason the session stores the
    /// raw status: the dock has to be able to say "stopped with an error", while a
    /// widget offering Stop for an app that already died would be worse than one
    /// showing nothing.
    @Test("a crashed app stays on the session after it leaves the widget snapshot")
    func keepsTerminalStatusesOnTheSession() async throws {
        let stores = try makeStores()
        let client = AppsRobotClient()
        let session = try await connected(client, stores: stores)
        _ = try await session.startApp(named: "dance_party")

        client.setRunning(AppsRobotClient.status(name: "dance_party", state: "error"))
        _ = try await session.currentApp()

        #expect(session.runningApp?.state == .error)
        #expect(stores.snapshots.current?.runningAppName == nil)
    }

    /// A dock left floating over the connection screen is exactly the bug this
    /// prevents — and `resetConnectionState` is the only place that can.
    @Test("disconnecting forgets what was running")
    func forgetsTheRunningAppOnDisconnect() async throws {
        let session = try await connected(AppsRobotClient())
        _ = try await session.startApp(named: "dance_party")

        session.disconnect()

        #expect(session.runningApp == nil)
    }

    @Test("an empty installed response keeps the last widget menu")
    func preservesTheMenuOverAnEmptyResponse() async throws {
        let stores = try makeStores()
        let client = AppsRobotClient()
        let session = try await connected(client, stores: stores)
        _ = try await session.installedApps()
        client.returnsEmptyInstalled = true

        _ = try await session.installedApps(refresh: true)

        #expect(stores.apps.current(for: "hw")?.installed.map(\.name) == ["dance_party"])
    }

    /// The three-second status poll does not learn what the robot is running —
    /// naming it would cost a round trip of its own. So it must carry the last
    /// answer forward rather than blank it, or the widget's running app survives
    /// exactly three seconds.
    @Test("the status poll does not forget the running app")
    func pollDoesNotClobberTheRunningApp() async throws {
        let stores = try makeStores()
        let session = try await connected(AppsRobotClient(), stores: stores)
        _ = try await session.startApp(named: "dance_party")

        let appReading = try #require(stores.snapshots.current?.runningAppTakenAt)
        let pollDate = appReading.addingTimeInterval(60)
        session.recordSnapshot(
            identity: .init(hardwareID: "hw", name: "testbot", daemonVersion: "1.9.0"),
            at: pollDate
        )

        #expect(stores.snapshots.current?.runningAppName == "dance_party")
        #expect(stores.snapshots.current?.runningAppTakenAt == appReading)
        #expect(stores.snapshots.current?.takenAt == pollDate)
        #expect(stores.snapshots.current?.robotName == "testbot")
    }
}
