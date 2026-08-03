import Foundation
@testable import ReachyKit
import Testing

/// Mock daemon whose probe outcomes are scripted per call.
private final class MockRobotClient: RobotAPIClient, @unchecked Sendable {
    enum Probe { case ok, fail }

    private let lock = NSLock()
    private var probes: [Probe]
    private(set) var wakeCalls = 0
    private(set) var sleepCalls = 0
    let identity = RobotIdentity(hardwareID: "hw-1", name: "testbot", daemonVersion: "1.9.0")

    init(probes: [Probe]) {
        self.probes = probes
    }

    private var status: Components.Schemas.DaemonStatus {
        let json = """
        {"robot_name": "testbot", "state": "running", "wireless_version": false,
         "desktop_app_daemon": false, "simulation_enabled": true,
         "mockup_sim_enabled": false,
         "backend_status": {"motor_control_mode": "enabled", "error": null}}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Components.Schemas.DaemonStatus.self, from: Data(json.utf8))
    }

    func handshake() async throws -> RobotConnection.Handshake {
        .init(identity: identity, status: status)
    }

    func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        let probe: Probe = lock.withLock { probes.isEmpty ? .ok : probes.removeFirst() }
        guard probe == .ok else { throw URLError(.cannotConnectToHost) }
        return status
    }

    func wakeUp() async throws {
        wakeCalls += 1
    }

    func gotoSleep() async throws {
        sleepCalls += 1
    }
}

@MainActor
@Suite("RobotSession")
struct RobotSessionTests {
    private func makeSession(client: MockRobotClient, pollMs: Int = 20) -> RobotSession {
        var config = RobotSession.Configuration()
        config.pollInterval = .milliseconds(pollMs)
        return RobotSession(configuration: config) { _ in client }
    }

    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeout: Duration = .seconds(5)
    ) async {
        let start = ContinuousClock.now
        while !condition(), start.duration(to: .now) < timeout {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("handshake success connects and stores last address")
    func connects() async {
        let session = makeSession(client: MockRobotClient(probes: []))
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        #expect(session.phase == .connected(.init(hardwareID: "hw-1", name: "testbot", daemonVersion: "1.9.0")))
        #expect(KnownRobots.lastAddress?.host == "10.0.0.9")
        session.disconnect()
    }

    @Test("probe failure drops to unreachable immediately, recovery needs 2 consecutive successes")
    func hysteresis() async {
        let client = MockRobotClient(probes: [.fail, .ok, .fail, .ok, .ok])
        let session = makeSession(client: client)
        await session.connect(to: RobotAddress(host: "10.0.0.9"))

        // fail → unreachable at the first probe
        await waitUntil({
            if case .unreachable = session.phase {
                true
            } else {
                false
            }
        }())
        guard case .unreachable = session.phase else {
            Issue.record("expected unreachable, got \(session.phase)")
            return
        }

        // ok, fail → still unreachable (single success is not enough, then reset)
        // ok, ok → connected again
        await waitUntil({
            if case .connected = session.phase {
                true
            } else {
                false
            }
        }())
        guard case .connected = session.phase else {
            Issue.record("expected connected after 2 consecutive successes, got \(session.phase)")
            return
        }
        session.disconnect()
    }

    @Test("handshake failure returns to idle with error")
    func handshakeFailure() async {
        struct FailingClient: RobotAPIClient {
            func handshake() async throws -> RobotConnection.Handshake {
                throw URLError(.timedOut)
            }

            func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
                throw URLError(.timedOut)
            }

            func wakeUp() async throws {}
            func gotoSleep() async throws {}
        }
        let session = RobotSession { _ in FailingClient() }
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        #expect(session.phase == .idle)
        #expect(session.lastError != nil)
    }

    @Test("wake and sleep forward to the client")
    func wakeSleep() async {
        let client = MockRobotClient(probes: [])
        let session = makeSession(client: client)
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        await session.wake()
        await session.sleep()
        #expect(client.wakeCalls == 1)
        #expect(client.sleepCalls == 1)
        session.disconnect()
    }
}
