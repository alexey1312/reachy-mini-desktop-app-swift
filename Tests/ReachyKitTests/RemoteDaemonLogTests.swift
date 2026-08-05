import Foundation
@testable import ReachyKit
import Testing

/// Carries broadcasts in and records what went out. `subscribe_logs` is answered
/// with nothing by the real daemon, so nothing is scripted here either.
private final class LogChannel: RemoteDataChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<String>.Continuation?
    private var pending: [String] = []
    private var recorded: [String] = []

    let isOpen = true

    var sent: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation != nil
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

    func close() {
        lock.lock()
        let listener = continuation
        continuation = nil
        lock.unlock()
        listener?.finish()
    }
}

@Suite("Remote daemon log", .timeLimit(.minutes(1)))
struct RemoteDaemonLogTests {
    private func log() -> (RemoteDaemonLog, LogChannel) {
        let channel = LogChannel()
        return (RemoteDaemonLog(control: RemoteControlChannel(channel: channel)), channel)
    }

    /// The daemon starts with the last 100 lines the moment it is asked, so the
    /// subscription has to be in place before the command goes out.
    @Test("subscribing sends subscribe_logs")
    func sendsSubscribeLogs() async throws {
        let (log, channel) = log()

        let stream = log.lines()
        while channel.sent.isEmpty {
            await Task.yield()
        }

        let sent = try #require(channel.sent.first)
        let object = try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any]
        #expect(object?["type"] as? String == "subscribe_logs")
        // Held to the end: releasing it would unsubscribe mid-assertion.
        _ = stream
    }

    /// `journalctl --output short-iso` puts one space between the timestamp and
    /// the record; the daemon splits them so a consumer can render them apart.
    /// Rejoining them is what lets `LogEntry` stay a single parser across both
    /// transports.
    @Test("a log line arrives in the shape the WebSocket route yields")
    func rejoinsTimestampAndLine() async throws {
        let (log, channel) = log()
        var lines = log.lines().makeAsyncIterator()
        while !channel.isListening {
            await Task.yield()
        }

        channel.emit(#"""
        {"type":"log_line","timestamp":"2026-08-05T09:12:01+0200","line":"INFO reachy_mini.daemon: up"}
        """#)

        let line = try #require(await lines.next())
        #expect(line == "2026-08-05T09:12:01+0200 INFO reachy_mini.daemon: up")
    }

    /// A record with no timestamp prefix is sent with an empty one rather than
    /// dropped, and must not gain a leading space.
    @Test("a line with no timestamp is not padded")
    func handlesAMissingTimestamp() async {
        let (log, channel) = log()
        var lines = log.lines().makeAsyncIterator()
        while !channel.isListening {
            await Task.yield()
        }

        channel.emit(#"{"type":"log_line","timestamp":"","line":"bare"}"#)

        #expect(await lines.next() == "bare")
    }

    /// The 50 Hz pose broadcast shares this channel. A console must not show it.
    @Test("other broadcasts are not mistaken for journal lines")
    func ignoresOtherBroadcasts() async {
        let (log, channel) = log()
        var lines = log.lines().makeAsyncIterator()
        while !channel.isListening {
            await Task.yield()
        }

        channel.emit(#"{"type":"joint_positions","positions":[0.1,0.2]}"#)
        channel.emit(#"{"type":"log_line","timestamp":"t","line":"wanted"}"#)

        #expect(await lines.next() == "t wanted")
    }

    /// "journalctl not found" is the answer to why the console went quiet — on a
    /// development host it is the *usual* answer — so it is shown as a line rather
    /// than swallowed. The subscription is over after it, and the stream says so.
    @Test("a stream error is surfaced and ends the stream")
    func surfacesAStreamError() async {
        let (log, channel) = log()
        var received: [String] = []
        let stream = log.lines()
        while !channel.isListening {
            await Task.yield()
        }

        channel.emit(#"{"type":"log_stream_error","error":"journalctl not found"}"#)

        for await line in stream {
            received.append(line)
        }
        #expect(received == ["ERROR log stream: journalctl not found"])
    }

    /// Leaving the console must stop the robot streaming its journal at us.
    @Test("ending the stream unsubscribes")
    func unsubscribesOnTermination() async {
        let (log, channel) = log()
        var iterator: AsyncStream<String>.Iterator? = log.lines().makeAsyncIterator()
        while !channel.isListening {
            await Task.yield()
        }

        iterator = nil
        _ = iterator

        while !channel.sent.contains(where: { $0.contains("unsubscribe_logs") }) {
            await Task.yield()
        }
        #expect(channel.sent.contains { $0.contains("unsubscribe_logs") })
    }

    /// The session ending is the subscription ending — a console left frozen with
    /// no explanation is the failure this prevents.
    @Test("a closed channel finishes the stream")
    func finishesWhenTheChannelCloses() async {
        let (log, channel) = log()
        let stream = log.lines()
        while !channel.isListening {
            await Task.yield()
        }

        channel.close()

        var received = 0
        for await _ in stream {
            received += 1
        }
        #expect(received == 0)
    }
}
