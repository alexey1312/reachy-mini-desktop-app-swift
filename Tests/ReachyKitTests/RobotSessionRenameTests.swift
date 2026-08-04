import Foundation
@testable import ReachyKit
import Testing

private final class RenameStubClient: RobotAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private let stored: String?
    private var requested: [String] = []

    /// `nil` makes the daemon reject the name with a 422, as it does for an empty
    /// or over-long one.
    init(stored: String?) {
        self.stored = stored
    }

    var requestedNames: [String] {
        lock.withLock { requested }
    }

    private var status: Components.Schemas.DaemonStatus {
        let json = """
        {"robot_name": "old-name", "state": "running", "wireless_version": true,
         "desktop_app_daemon": false, "version": "1.9.0", "backend_status": null}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Components.Schemas.DaemonStatus.self, from: Data(json.utf8))
    }

    func handshake() async throws -> RobotConnection.Handshake {
        .init(identity: RobotIdentity(hardwareID: "hw", name: "old-name", daemonVersion: "1.9.0"), status: status)
    }

    func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        status
    }

    func wakeUp() async throws -> String {
        "uuid"
    }

    func gotoSleep() async throws -> String {
        "uuid"
    }

    func setRobotName(_ name: String) async throws -> String {
        lock.withLock { requested.append(name) }
        guard let stored else { throw ReachyKitError.daemonRejected(statusCode: 422) }
        return stored
    }
}

@MainActor
@Suite("RobotSession rename")
struct RobotSessionRenameTests {
    private func connectedSession(_ client: RenameStubClient) async -> RobotSession {
        let session = RobotSession { _ in client }
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        return session
    }

    @Test("the live identity follows what the daemon stored, not what was typed")
    func adoptsTheStoredName() async throws {
        let client = RenameStubClient(stored: "kitchen-reachy")
        let session = await connectedSession(client)

        let stored = try await session.rename(to: "Kitchen Reachy")

        #expect(stored == "kitchen-reachy")
        #expect(client.requestedNames == ["Kitchen Reachy"])
        #expect(session.phase == .connected(
            RobotIdentity(hardwareID: "hw", name: "kitchen-reachy", daemonVersion: "1.9.0")
        ))
    }

    @Test("a rejected name leaves the identity alone")
    func keepsTheOldNameOnRejection() async {
        let session = await connectedSession(RenameStubClient(stored: nil))

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 422)) {
            _ = try await session.rename(to: "")
        }
        #expect(session.phase == .connected(
            RobotIdentity(hardwareID: "hw", name: "old-name", daemonVersion: "1.9.0")
        ))
    }
}
