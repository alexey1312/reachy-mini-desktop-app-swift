import Foundation
@testable import ReachyKit
import simd
import Testing

/// Records what went out. `set_full_target` is sent rather than performed, so
/// nothing needs scripting.
private final class TeleopChannelSpy: RemoteDataChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    let isOpen = true

    var sent: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ text: String) async throws {
        record(text)
    }

    /// Synchronous on purpose: `NSLock` is `noasync`, because a lock held across
    /// a suspension is a deadlock waiting for the right scheduling.
    private func record(_ text: String) {
        lock.lock()
        recorded.append(text)
        lock.unlock()
    }

    func messages() -> AsyncStream<String> {
        AsyncStream { _ in }
    }
}

@Suite("Remote teleop channel", .timeLimit(.minutes(1)))
struct RemoteTeleopChannelTests {
    private func teleop(
        minSendInterval: Duration = .milliseconds(33)
    ) -> (RemoteTeleopChannel, TeleopChannelSpy) {
        let spy = TeleopChannelSpy()
        return (
            RemoteTeleopChannel(
                control: RemoteControlChannel(channel: spy),
                minSendInterval: minSendInterval
            ),
            spy
        )
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// One command where the LAN socket sends one frame: `set_target` alone would
    /// need `set_body_yaw` and `set_antennas` beside it and make every frame three.
    @Test("a target goes out as one set_full_target")
    func sendsOneCommand() async throws {
        let (teleop, spy) = teleop()

        await teleop.send(TeleopTarget(yaw: 0.2, bodyYaw: 0.3, antennaLeft: 0.4, antennaRight: -0.4))

        #expect(spy.sent.count == 1)
        let body = try object(#require(spy.sent.first))
        #expect(body["type"] as? String == "set_full_target")
        #expect((body["head"] as? [Double])?.count == 16)
        #expect(body["antennas"] as? [Double] == [0.4, -0.4])
        #expect(body["body_yaw"] as? Double == 0.3)
    }

    /// The one test that matters here. Both transports carry the *same pose*, and
    /// the only thing that could silently differ is the euler convention: the LAN
    /// route sends XYZRPY and the daemon composes the matrix itself with
    /// `R.from_euler("xyz", …)`, while this side composes it and sends the result.
    /// Getting that wrong moves the robot somewhere else with no error anywhere.
    ///
    /// So the LAN payload is decoded back, run through the same composition the
    /// daemon performs, and compared element by element with what this channel put
    /// on the wire.
    @Test("the matrix on the wire is the pose the LAN route describes")
    func matchesTheLANPose() async throws {
        let target = TeleopTarget(
            x: 0.01, y: -0.02, z: 0.03,
            roll: 0.15, pitch: -0.25, yaw: 0.35,
            bodyYaw: 0.45, antennaLeft: 0.55, antennaRight: -0.65
        )
        let (teleop, spy) = teleop()

        await teleop.send(target)

        // What the LAN client would have sent, read back as the daemon reads it.
        let encoded = try #require(String(bytes: SetTargetClient.encode(target), encoding: .utf8))
        let lan = try object(encoded)
        let head = try #require(lan["target_head_pose"] as? [String: Double])
        let composed = try RigidTransform.transform(
            translation: SIMD3(#require(head["x"]), #require(head["y"]), #require(head["z"])),
            rpy: SIMD3(#require(head["roll"]), #require(head["pitch"]), #require(head["yaw"]))
        )
        let expected = RigidTransform.rowMajorValues(composed)

        let body = try object(#require(spy.sent.first))
        let actual = try #require(body["head"] as? [Double])
        #expect(actual.count == expected.count)
        for (sent, wanted) in zip(actual, expected) {
            #expect(abs(sent - wanted) < 1e-12)
        }
        // And the two halves the daemon does not transform at all.
        #expect(body["antennas"] as? [Double] == lan["target_antennas"] as? [Double])
        #expect(body["body_yaw"] as? Double == lan["target_body_yaw"] as? Double)
    }

    /// The bottom row of a rigid transform, which is what tells a row-major
    /// flatten from a column-major one when the rotation happens to be symmetric.
    @Test("the head matrix is flattened row by row")
    func flattensRowMajor() async throws {
        let (teleop, spy) = teleop()

        await teleop.send(TeleopTarget(x: 1, y: 2, z: 3))

        let body = try object(#require(spy.sent.first))
        let head = try #require(body["head"] as? [Double])
        // Translation lives in the last column of each of the first three rows.
        #expect(head[3] == 1)
        #expect(head[7] == 2)
        #expect(head[11] == 3)
        #expect(Array(head[12 ..< 16]) == [0, 0, 0, 1])
    }

    /// The UI emits at gesture rate; the wire should not. Same budget as the LAN
    /// client, and latest-wins rather than queued.
    @Test("a burst is throttled to one frame")
    func throttlesABurst() async {
        let (teleop, spy) = teleop(minSendInterval: .seconds(30))

        await teleop.send(TeleopTarget(yaw: 0.1))
        await teleop.send(TeleopTarget(yaw: 0.2))
        await teleop.send(TeleopTarget(yaw: 0.3))

        #expect(spy.sent.count == 1)
    }

    /// This rides a channel the peer connection opened long before a joystick
    /// existed. Closing it would end the session the robot is being driven over.
    @Test("connecting and disconnecting leave the channel alone")
    func doesNotOwnTheChannel() async {
        let (teleop, spy) = teleop()

        await teleop.connect()
        await teleop.disconnect()

        #expect(spy.sent.isEmpty)
    }
}
