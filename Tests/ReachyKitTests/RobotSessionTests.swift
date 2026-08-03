import Foundation
@testable import ReachyKit
import Testing

/// Mock daemon whose probe outcomes are scripted per call.
private final class MockRobotClient: RobotAPIClient, @unchecked Sendable {
    enum Probe { case ok, fail }

    /// Every daemon call in order, so tests can assert the wake/sleep sequence.
    enum Step: Equatable {
        case startDaemon(wakeUp: Bool)
        case motorMode(Components.Schemas.MotorControlMode)
        case wakeUp
        case gotoSleep
    }

    private let lock = NSLock()
    private var probes: [Probe]
    private var state: Components.Schemas.DaemonState
    private var steps: [Step] = []
    let identity = RobotIdentity(hardwareID: "hw-1", name: "testbot", daemonVersion: "1.9.0")

    private let wakeFailure: ReachyKitError?
    private let startFailure: ReachyKitError?

    init(
        probes: [Probe],
        state: Components.Schemas.DaemonState = .running,
        wakeFailure: ReachyKitError? = nil,
        startFailure: ReachyKitError? = nil
    ) {
        self.probes = probes
        self.state = state
        self.wakeFailure = wakeFailure
        self.startFailure = startFailure
    }

    var recordedSteps: [Step] {
        lock.withLock { steps }
    }

    var wakeCalls: Int {
        recordedSteps.filter { $0 == .wakeUp }.count
    }

    var sleepCalls: Int {
        recordedSteps.filter { $0 == .gotoSleep }.count
    }

    private func record(_ step: Step) {
        lock.withLock { steps.append(step) }
    }

    private var status: Components.Schemas.DaemonStatus {
        let currentState = lock.withLock { state }
        let json = """
        {"robot_name": "testbot", "state": "\(currentState.rawValue)", "wireless_version": false,
         "desktop_app_daemon": false, "simulation_enabled": true,
         "mockup_sim_enabled": false,
         "backend_status": {"ready": true, "motor_control_mode": "enabled",
                            "last_alive": null, "control_loop_stats": {}}}
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

    func wakeUp() async throws -> String {
        if let wakeFailure {
            throw wakeFailure
        }
        record(.wakeUp)
        return "wake-uuid"
    }

    func gotoSleep() async throws -> String {
        record(.gotoSleep)
        return "sleep-uuid"
    }

    func setMotorMode(_ mode: Components.Schemas.MotorControlMode) async throws {
        record(.motorMode(mode))
    }

    /// The real route answers with a job id and starts the backend in the background.
    func startDaemon(wakeUp: Bool) async throws {
        if let startFailure {
            throw startFailure
        }
        record(.startDaemon(wakeUp: wakeUp))
        lock.withLock { state = .running }
    }

    func runningMoveUUIDs() async throws -> Set<String> {
        []
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

            func wakeUp() async throws -> String {
                ""
            }

            func gotoSleep() async throws -> String {
                ""
            }
        }
        let session = RobotSession { _ in FailingClient() }
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        #expect(session.phase == .idle)
        #expect(session.lastError != nil)
    }

    @Test("wake enables the motors before playing the animation")
    func wakeEnablesMotorsFirst() async {
        let client = MockRobotClient(probes: [])
        let session = makeSession(client: client)
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        await session.wake()
        #expect(client.recordedSteps == [.motorMode(.enabled), .wakeUp])
        session.disconnect()
    }

    @Test("wake starts a stopped backend instead of hitting 503")
    func wakeStartsStoppedDaemon() async {
        let client = MockRobotClient(probes: [], state: .stopped)
        let session = makeSession(client: client)
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        await session.wake()
        // `wake_up=true` makes the daemon enable the motors and play the animation itself.
        #expect(client.recordedSteps.first == .startDaemon(wakeUp: true))
        #expect(session.lastError == nil)
        session.disconnect()
    }

    @Test("a 503 from a torn-down backend reads as an actionable message")
    func backendNotRunningIsReadable() async {
        let client = MockRobotClient(probes: [], wakeFailure: .backendNotRunning)
        let session = makeSession(client: client)
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        await session.wake()
        #expect(session.lastError == ReachyKitError.backendNotRunning.errorDescription)
        #expect(session.powerTransition == nil)
        session.disconnect()
    }

    @Test("a 409 while the daemon is busy reads as an actionable message")
    func daemonBusyIsReadable() async {
        let client = MockRobotClient(probes: [], state: .stopped, startFailure: .daemonBusy)
        let session = makeSession(client: client)
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        await session.wake()
        #expect(session.lastError == ReachyKitError.daemonBusy.errorDescription)
        session.disconnect()
    }

    @Test("a second wake is ignored while one is already in flight")
    func concurrentWakeIsIgnored() async {
        let client = MockRobotClient(probes: [])
        let session = makeSession(client: client)
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        async let first: Void = session.wake()
        async let second: Void = session.wake()
        _ = await (first, second)
        #expect(client.wakeCalls == 1)
        session.disconnect()
    }

    @Test("sleep disables the motors only after the animation finished")
    func sleepDisablesMotorsLast() async {
        let client = MockRobotClient(probes: [])
        let session = makeSession(client: client)
        await session.connect(to: RobotAddress(host: "10.0.0.9"))
        await session.sleep()
        #expect(client.recordedSteps == [.gotoSleep, .motorMode(.disabled)])
        session.disconnect()
    }
}
