import Foundation
@testable import ReachyKit
import Testing

/// Answers the daemon's own shapes, taken from `process_command` in
/// `daemon/backend/abstract.py` rather than invented.
private final class ScriptedChannel: RemoteDataChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<String>.Continuation?
    private var pending: [String] = []
    private var recorded: [String] = []
    private let scripted: [String: String]

    init(_ replies: [String: String]) {
        scripted = replies
    }

    var sent: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// These tests are about what the commands say, not about how long they may
    /// take, so the channel is simply up throughout.
    let isOpen = true

    func send(_ text: String) async throws {
        guard let reply = record(text) else { return }
        emit(reply)
    }

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

@Suite("Remote robot connection", .timeLimit(.minutes(1)))
struct RemoteRobotConnectionTests {
    private static let identity = [
        "get_version": #"{"version":"1.9.0"}"#,
        "get_hardware_id": #"{"hardware_id":"a1b2c3d4e5f60718"}"#,
    ]

    private func connection(
        _ replies: [String: String] = [:],
        robotName: String? = "reachy-mini"
    ) -> (RemoteRobotConnection, ScriptedChannel) {
        let channel = ScriptedChannel(Self.identity.merging(replies) { _, new in new })
        return (
            RemoteRobotConnection(channel: channel, robotName: robotName, timeout: .seconds(5)),
            channel
        )
    }

    /// Neither command echoes its name back, so both are only findable by the key
    /// they carry — the case the channel's `replyKey` correlation exists for.
    @Test("the handshake reads version and hardware id off the channel")
    func handshakeReadsIdentity() async throws {
        let (connection, _) = connection()

        let handshake = try await connection.handshake()

        #expect(handshake.identity.daemonVersion == "1.9.0")
        #expect(handshake.identity.hardwareID == "a1b2c3d4e5f60718")
    }

    /// The channel cannot report a name — no command answers one — so it comes
    /// from the central listing that got us to this robot in the first place.
    @Test("the robot's name comes from the listing, not the channel")
    func nameComesFromTheListing() async throws {
        let (connection, _) = connection(robotName: "kitchen bot")

        let handshake = try await connection.handshake()

        #expect(handshake.identity.name == "kitchen bot")
        #expect(handshake.status.robotName == "kitchen bot")
    }

    /// `/wifi/*` and `/update/*` are HTTP routes on the robot's own network, so
    /// they are genuinely out of reach here. Reporting the robot as non-wireless
    /// is what closes those screens, and it closes them for a true reason.
    @Test("a remote robot reports no wireless features")
    func reportsNoWirelessFeatures() async throws {
        let (connection, _) = connection()

        let status = try await connection.daemonStatus()

        #expect(status.wirelessVersion == false)
        #expect(status.state == .running)
    }

    @Test("waking up sends the command and waits for the move to finish")
    func wakesUp() async throws {
        let (connection, channel) = connection([
            "wake_up": #"{"status":"ok","command":"wake_up","completed":true}"#,
        ])

        _ = try await connection.wakeUp()

        #expect(channel.sent.contains { $0.contains("\"wake_up\"") })
    }

    /// The robot answers a failure on the same channel, as a field rather than a
    /// status code, and the message is its own.
    @Test("a refused wake-up surfaces the robot's message")
    func surfacesARefusal() async {
        let (connection, _) = connection([
            "wake_up": #"{"error":"Backend not running","command":"wake_up"}"#,
        ])

        await #expect(throws: RemoteControlChannel.Failure.robot("Backend not running")) {
            _ = try await connection.wakeUp()
        }
    }

    /// The data channel's volume reply is `{"command": …, "volume": …}` — a level
    /// and nothing else, where the REST route also names the sink.
    @Test("volume comes back without a device to name")
    func readsVolume() async throws {
        let (connection, _) = connection([
            "get_volume": #"{"command":"get_volume","volume":65}"#,
        ])

        let level = try await connection.volume()

        #expect(level.percent == 65)
        #expect(level.device == nil)
        #expect(level.platform == nil)
    }

    /// The daemon answers `set_volume` with the level it settled on, which is not
    /// the requested one when the platform refuses it.
    @Test("a rejected volume comes back at the level the robot kept")
    func reportsTheVolumeTheRobotKept() async throws {
        let (connection, _) = connection([
            "set_volume": #"{"status":"error","command":"set_volume","volume":30}"#,
        ])

        let level = try await connection.setVolume(80)

        #expect(level.percent == 30)
    }

    /// Nothing on this channel serves `/api/kinematics/*` or the move datasets, so
    /// the protocol's throwing defaults stand rather than a stub that pretends.
    @Test("routes the channel does not carry stay unimplemented")
    func leavesUnreachableRoutesAlone() async {
        let (connection, _) = connection()

        await #expect(throws: (any Error).self) {
            _ = try await connection.urdf()
        }
        await #expect(throws: (any Error).self) {
            _ = try await connection.listMoves(dataset: "default")
        }
    }
}
