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
