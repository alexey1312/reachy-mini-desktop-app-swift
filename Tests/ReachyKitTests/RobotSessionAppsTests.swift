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
    var failsCatalogue = false

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
        return [Self.app(name: "reachy-mini-dance", kind: "hf_space")]
    }

    func installedApps() async throws -> [RobotApp] {
        lock.withLock { installedCalls += 1 }
        return [Self.app(name: "dance_party", kind: "installed")]
    }

    func removeApp(named name: String) async throws -> String {
        lock.withLock { removed.append(name) }
        return "job-1"
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
    private func connected(_ client: any RobotAPIClient) async -> RobotSession {
        let session = RobotSession { _ in client }
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
    func reportsMissingCapability() async {
        let session = await connected(PlainRobotClient())

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
        let session = await connected(client)

        _ = try await session.appCatalogue()
        _ = try await session.appCatalogue()
        #expect(client.catalogueCalls == 1)

        _ = try await session.appCatalogue(refresh: true)
        #expect(client.catalogueCalls == 2)
    }

    @Test("removing an app makes the installed list stale at once")
    func removalInvalidatesTheInstalledList() async throws {
        let client = AppsRobotClient()
        let session = await connected(client)

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
        let session = await connected(client)

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
        let session = await connected(client)

        _ = try await session.appCatalogue()
        session.disconnect()
        _ = await session.connect(to: .init(host: "127.0.0.1"))
        _ = try await session.appCatalogue()

        #expect(client.catalogueCalls == 2)
    }
}
