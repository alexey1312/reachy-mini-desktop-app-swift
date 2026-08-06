import Foundation
@testable import ReachyKit
import Testing

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
    private func makeStores() throws -> AppSessionStores {
        try .make("RobotSessionAppsTests")
    }

    private func connected(
        _ client: any RobotAPIClient,
        stores: AppSessionStores? = nil
    ) async throws -> RobotSession {
        try await connectedAppSession(client, stores: stores ?? makeStores())
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
    /// raw status: a widget offering Stop for an app that already died would be
    /// worse than one showing nothing, so the crash travels on its own field —
    /// never as the app that is running.
    @Test("a crashed app stays on the session and reaches the snapshot as a failure")
    func keepsTerminalStatusesOnTheSession() async throws {
        let stores = try makeStores()
        let client = AppsRobotClient()
        let session = try await connected(client, stores: stores)
        _ = try await session.startApp(named: "dance_party")

        client.setRunning(AppsRobotClient.status(
            name: "dance_party",
            state: "error",
            error: "ImportError: no module named cv2"
        ))
        _ = try await session.currentApp()

        #expect(session.runningApp?.state == .error)
        #expect(stores.snapshots.current?.runningAppName == nil)
        #expect(stores.snapshots.current?.failedApp?.name == "dance_party")
        #expect(stores.snapshots.current?.failedApp?.error == "ImportError: no module named cv2")
        // The reading is only worth expiring if it is dated, and the running-app
        // date is what dates it.
        #expect(stores.snapshots.current?.runningAppTakenAt != nil)
    }

    /// An app that ran to completion is not a failure. Reporting one would put a
    /// warning badge on every tile whose app simply finished.
    @Test("an app that finished is not recorded as a failure")
    func doesNotReportAFinishedAppAsAFailure() async throws {
        let stores = try makeStores()
        let client = AppsRobotClient()
        let session = try await connected(client, stores: stores)
        client.setRunning(AppsRobotClient.status(name: "dance_party", state: "done"))

        _ = try await session.currentApp()

        #expect(stores.snapshots.current?.failedApp == nil)
    }

    /// One reading of one question: whoever saw a live app thereby saw no crash.
    @Test("starting an app again clears the crash it left behind")
    func clearsAFailureOnTheNextStart() async throws {
        let stores = try makeStores()
        let client = AppsRobotClient()
        let session = try await connected(client, stores: stores)
        client.setRunning(AppsRobotClient.status(name: "dance_party", state: "error", error: "boom"))
        _ = try await session.currentApp()
        #expect(stores.snapshots.current?.failedApp != nil)

        _ = try await session.startApp(named: "dance_party")

        #expect(stores.snapshots.current?.failedApp == nil)
        #expect(stores.snapshots.current?.runningAppName == "dance_party")
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

    /// The same trap one field over: a poll that blanked the crash would have the
    /// widget forget it three seconds after learning it.
    @Test("the status poll does not forget a crash either")
    func pollDoesNotClobberAFailure() async throws {
        let stores = try makeStores()
        let client = AppsRobotClient()
        let session = try await connected(client, stores: stores)
        client.setRunning(AppsRobotClient.status(name: "dance_party", state: "error", error: "boom"))
        _ = try await session.currentApp()

        let appReading = try #require(stores.snapshots.current?.runningAppTakenAt)
        session.recordSnapshot(
            identity: .init(hardwareID: "hw", name: "testbot", daemonVersion: "1.9.0"),
            at: appReading.addingTimeInterval(60)
        )

        #expect(stores.snapshots.current?.failedApp?.name == "dance_party")
        #expect(stores.snapshots.current?.runningAppTakenAt == appReading)
    }
}
