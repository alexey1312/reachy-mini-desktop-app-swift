import Foundation
import Network
@testable import ReachyKit
import Testing

@Suite("SetTargetClient")
struct SetTargetClientTests {
    @Test("wire format matches FullBodyTarget: snake_case keys, flat XYZRPY head pose")
    func wireFormat() throws {
        let target = SetTargetClient.Target(
            z: 0.01, pitch: 0.2, yaw: -0.3, bodyYaw: 0.5, antennaLeft: 0.1, antennaRight: -0.1
        )
        let json = try JSONSerialization.jsonObject(with: SetTargetClient.encode(target)) as? [String: Any]
        let head = json?["target_head_pose"] as? [String: Double]
        #expect(head?["pitch"] == 0.2)
        #expect(head?["yaw"] == -0.3)
        #expect(head?["z"] == 0.01)
        #expect(json?["target_body_yaw"] as? Double == 0.5)
        #expect(json?["target_antennas"] as? [Double] == [0.1, -0.1])
    }

    @Test("a step goal arrives as a run of frames, not one", .timeLimit(.minutes(1)))
    func pacing() async throws {
        let received = ReceivedCounter()
        let accepted = ReceivedCounter()
        let server = try LocalWebSocketServer { connection in
            accepted.increment()
            receiveLoop(connection, counter: received)
        }
        defer { server.stop() }
        let port = try await server.readyPort()

        let client = try SetTargetClient(
            address: RobotAddress(host: "127.0.0.1", port: Int(port)),
            tickInterval: .milliseconds(10)
        )
        await client.connect()
        // `connect()` returns before the handshake, so wait on the server actually
        // accepting rather than on a duration a loaded CI runner can overrun.
        await waitUntil(accepted.count >= 1)

        // Half a turn cannot be one frame: at the limiter's body ceiling it needs
        // more than a second, so the wire must carry the whole ramp.
        await client.send(.init(bodyYaw: .pi))
        await waitUntil(received.count >= 5)
        #expect(received.count >= 5)
        await client.disconnect()
    }

    @Test("the pacer goes quiet once it reaches the goal", .timeLimit(.minutes(1)))
    func quiescence() async throws {
        let received = ReceivedCounter()
        let accepted = ReceivedCounter()
        let server = try LocalWebSocketServer { connection in
            accepted.increment()
            receiveLoop(connection, counter: received)
        }
        defer { server.stop() }
        let port = try await server.readyPort()

        let client = try SetTargetClient(
            address: RobotAddress(host: "127.0.0.1", port: Int(port)),
            tickInterval: .milliseconds(10)
        )
        await client.connect()
        await waitUntil(accepted.count >= 1)

        await client.send(.init(yaw: 0.01))
        await waitUntil(received.count >= 1)
        // The condition is "the count holds still", not "some time has passed": the
        // tail of an exponential approach is short but not instant, and a loaded
        // runner stretches it. A pacer that never stopped never goes quiet, however
        // long the deadline.
        var settled = 0
        var quietTicks = 0
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline, quietTicks < 20 {
            try await Task.sleep(for: .milliseconds(10))
            if received.count == settled {
                quietTicks += 1
            } else {
                settled = received.count
                quietTicks = 0
            }
        }
        #expect(quietTicks >= 20, "the pacer never stopped transmitting")
        await client.disconnect()
    }

    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeout: Duration = .seconds(10)
    ) async {
        let start = ContinuousClock.now
        while !condition(), start.duration(to: .now) < timeout {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class ReceivedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}

private func receiveLoop(_ connection: NWConnection, counter: ReceivedCounter) {
    connection.receiveMessage { data, _, _, error in
        if data != nil {
            counter.increment()
        }
        if error == nil {
            receiveLoop(connection, counter: counter)
        }
    }
}
