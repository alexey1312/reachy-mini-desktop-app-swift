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

    @Test("throttle: a burst of sends collapses to one wire frame", .timeLimit(.minutes(1)))
    func throttle() async throws {
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
            minSendInterval: .seconds(10)
        )
        await client.connect()
        // `connect()` returns before the handshake, so wait on the server actually
        // accepting rather than on a duration a loaded CI runner can overrun.
        await waitUntil(accepted.count >= 1)

        for i in 0 ..< 5 {
            await client.send(.init(bodyYaw: Double(i)))
        }
        // The 10 s throttle means no second frame can follow, so the first arrival
        // is already the final count.
        await waitUntil(received.count >= 1)
        #expect(received.count == 1)
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
