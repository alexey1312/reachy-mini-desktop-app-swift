import Foundation
@testable import ReachyKit
import Testing

/// Integration tests against a live (simulated) daemon.
/// Skipped unless `REACHY_SIM_HOST` is set — run via `./bin/mise run test:sim`
/// with `./bin/mise run sim-daemon` active in another terminal.
@Suite(
    "Live simulator integration",
    .enabled(if: ProcessInfo.processInfo.environment["REACHY_SIM_HOST"] != nil)
)
struct SimulatorIntegrationTests {
    private var address: RobotAddress {
        RobotAddress(host: ProcessInfo.processInfo.environment["REACHY_SIM_HOST"] ?? "127.0.0.1")
    }

    @Test("handshake returns identity and daemon version")
    func handshake() async throws {
        let connection = try RobotConnection(address: address)
        let handshake = try await connection.handshake()
        #expect(handshake.identity.daemonVersion?.isEmpty == false)
        #expect(handshake.status.simulationEnabled == true)
    }

    @Test("set_target moves the head (visible in the state stream)", .timeLimit(.minutes(1)))
    func teleop() async throws {
        let client = try SetTargetClient(address: address, minSendInterval: .milliseconds(10))
        await client.connect()

        // Stream a yaw target for a while, then check the observed head pose moved.
        let targetYaw = 0.4
        let sender = Task {
            for _ in 0 ..< 40 {
                await client.send(.init(yaw: targetYaw))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        defer {
            sender.cancel()
            Task { await client.disconnect() }
        }

        let stream = try StateStreamClient(address: address)
        var bestYaw = 0.0
        for await state in stream.states() {
            if let yaw = state.headPose?.value1?.yaw {
                bestYaw = max(bestYaw, abs(yaw))
                if bestYaw > 0.2 {
                    break
                }
            }
        }
        #expect(bestYaw > 0.2, "head yaw should approach the streamed target")
    }

    @Test("state stream delivers ~20 Hz", .timeLimit(.minutes(1)))
    func stateStream() async throws {
        let client = try StateStreamClient(address: address)
        let start = ContinuousClock.now
        var count = 0
        for await state in client.states() {
            #expect(state.controlMode != nil)
            count += 1
            if count == 40 {
                break
            }
        }
        let elapsed = start.duration(to: .now)
        // 40 frames at 20 Hz ≈ 2 s; allow generous slack for CI-class machines
        #expect(elapsed < .seconds(10))
    }
}
