import Foundation
@testable import ReachyKit
import Testing

/// A data channel that answers whatever a test scripts, and records what it was
/// asked. Stands in for the reliable `"data"` channel the robot opens.
///
/// Locks by hand rather than through `withLock`. A closure nested inside the
/// `AsyncStream` builder, capturing the escaping continuation, hands the
/// compiler's `ClosureLifetimeFixup` SIL pass a `convert_escape_to_noescape` it
/// never finishes walking: the whole test module compiles forever, so no test
/// in it ever runs and the failure reads as a hang in the code under test.
private final class FakeDataChannel: RemoteDataChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<String>.Continuation?
    private var pending: [String] = []
    private var recorded: [String] = []
    /// Answers keyed by the command that provokes them.
    private let scripted: [String: String]

    init(replies: [String: String] = [:]) {
        scripted = replies
    }

    var sent: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ text: String) async throws {
        guard let reply = record(text) else { return }
        emit(reply)
    }

    /// Synchronous on purpose: `NSLock` is `noasync`, because a lock held across
    /// a suspension is a deadlock waiting for the right scheduling.
    private func record(_ text: String) -> String? {
        let command = try? JSONDecoder().decode(TypeOnly.self, from: Data(text.utf8)).type
        lock.lock()
        defer { lock.unlock() }
        recorded.append(text)
        guard let command else { return nil }
        return scripted[command]
    }

    func messages() -> AsyncStream<String> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            let backlog = pending
            pending = []
            lock.unlock()
            for text in backlog {
                continuation.yield(text)
            }
        }
    }

    /// Anything the robot says on its own — a broadcast, or a reply to something
    /// this test never sent.
    ///
    /// Buffered until someone is listening: a real channel is subscribed to before
    /// anything is sent, while here `send` can answer before the reader's task has
    /// had a chance to run, and a dropped reply would look exactly like a robot
    /// that went quiet.
    func emit(_ text: String) {
        lock.lock()
        let listener = continuation
        if listener == nil {
            pending.append(text)
        }
        lock.unlock()
        listener?.yield(text)
    }

    private struct TypeOnly: Decodable {
        let type: String
    }
}

@Suite("Remote control channel", .timeLimit(.minutes(1)))
struct RemoteControlChannelTests {
    private func channel(
        _ replies: [String: String] = [:],
        timeout: Duration = .seconds(5)
    ) -> (RemoteControlChannel, FakeDataChannel) {
        let fake = FakeDataChannel(replies: replies)
        return (RemoteControlChannel(channel: fake, timeout: timeout), fake)
    }

    /// The robot answers by echoing the command back. There is no request id on
    /// this channel — the echoed `command` is the whole of the correlation.
    @Test("a command is matched to its reply by the command it echoes")
    func matchesByEchoedCommand() async throws {
        let (control, fake) = channel([
            "wake_up": #"{"status":"ok","command":"wake_up","completed":true}"#,
        ])

        try await control.perform("wake_up")

        let sent = try #require(fake.sent.first)
        #expect(sent.contains("\"type\":\"wake_up\"") || sent.contains("\"type\" : \"wake_up\""))
    }

    /// A failure comes back on the same channel, as a field rather than a status
    /// code, and carries the robot's own words.
    @Test("an error reply is thrown with the robot's own message")
    func throwsTheRobotsError() async {
        let (control, _) = channel([
            "wake_up": #"{"error":"Backend not running","command":"wake_up"}"#,
        ])

        await #expect(throws: RemoteControlChannel.Failure.robot("Backend not running")) {
            try await control.perform("wake_up")
        }
    }

    /// The robot broadcasts things nobody asked for — move progress, for one — and
    /// a reply to a command still in flight must not be lost among them.
    @Test("an unsolicited message does not satisfy a pending command")
    func ignoresUnrelatedMessages() async throws {
        let (control, fake) = channel()

        async let reply = control.perform("wake_up")
        try await Task.sleep(for: .milliseconds(50))
        fake.emit(#"{"type":"play_uploaded_move","upload_id":"u1","finished":true}"#)
        fake.emit(#"{"status":"ok","command":"goto_sleep","completed":true}"#)
        fake.emit(#"{"status":"ok","command":"wake_up","completed":true}"#)

        _ = try await reply
    }

    /// Nothing on this channel says how long a command may take, and a caller left
    /// awaiting forever is worse than one told the robot went quiet.
    @Test("a command the robot never answers gives up")
    func timesOut() async {
        let (control, _) = channel(timeout: .milliseconds(100))

        await #expect(throws: RemoteControlChannel.Failure.timedOut) {
            try await control.perform("wake_up")
        }
    }

    /// Not every reply echoes a command: `get_version` answers a bare
    /// `{"version": …}`, `get_hardware_id` a bare `{"hardware_id": …}`. The caller
    /// says which key identifies its reply, because nothing on the wire does.
    @Test("a reply that echoes no command is matched by the key it carries")
    func matchesByReplyKey() async throws {
        let (control, _) = channel(["get_version": #"{"version":"1.9.0"}"#])

        struct Reply: Decodable {
            let version: String
        }

        let reply = try await control.perform(
            "get_version",
            correlation: .replyKey("version"),
            expecting: Reply.self
        )

        #expect(reply.version == "1.9.0")
    }

    /// Telemetry always names a `type` and never a `command`. One of those
    /// broadcasts carries a `state` of its own, so a caller waiting on `get_state`
    /// must not take the first message that happens to hold the key.
    @Test("a broadcast is not mistaken for the keyed reply it resembles")
    func ignoresABroadcastCarryingTheSameKey() async throws {
        let (control, fake) = channel()

        async let reply = control.perform("get_state", correlation: .replyKey("state"))
        try await Task.sleep(for: .milliseconds(50))
        fake.emit(#"{"type":"daemon_status","robot_name":"reachy","state":"running"}"#)
        fake.emit(#"{"state":{"body_yaw":0.5}}"#)

        let data = try await reply
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["type"] == nil)
    }

    @Test("a reply with a payload comes back decoded")
    func decodesAPayload() async throws {
        let (control, _) = channel([
            "get_state": #"""
            {"command":"get_state","state":{"body_yaw":0.5,"motor_mode":"enabled","is_move_running":false}}
            """#,
        ])

        struct State: Decodable, Equatable {
            let bodyYaw: Double
            let motorMode: String

            enum CodingKeys: String, CodingKey {
                case bodyYaw = "body_yaw"
                case motorMode = "motor_mode"
            }
        }
        struct Reply: Decodable {
            let state: State
        }

        let reply = try await control.perform("get_state", expecting: Reply.self)

        #expect(reply.state == State(bodyYaw: 0.5, motorMode: "enabled"))
    }

    /// Two commands of the same name cannot be told apart on the wire, so they are
    /// not allowed to be in flight together — the second would take the first's
    /// reply.
    @Test("the same command twice runs one after the other")
    func serialisesIdenticalCommands() async throws {
        let (control, fake) = channel([
            "wake_up": #"{"status":"ok","command":"wake_up","completed":true}"#,
        ])

        async let first = control.perform("wake_up")
        async let second = control.perform("wake_up")
        _ = try await first
        _ = try await second

        #expect(fake.sent.count == 2)
    }

    /// Commands carry parameters, and the robot's models name them its way.
    @Test("a payload is sent alongside the command type")
    func sendsAPayload() async throws {
        let (control, fake) = channel([
            "set_volume": #"{"status":"ok","command":"set_volume","completed":true}"#,
        ])

        try await control.perform("set_volume", payload: ["volume": .number(42)])

        let sent = try #require(fake.sent.first)
        let object = try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any]
        #expect(object?["type"] as? String == "set_volume")
        #expect(object?["volume"] as? Double == 42)
    }
}
