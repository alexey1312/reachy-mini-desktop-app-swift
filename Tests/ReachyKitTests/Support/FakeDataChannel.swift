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
final class FakeDataChannel: RemoteDataChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<String>.Continuation?
    private var pending: [String] = []
    private var recorded: [String] = []
    /// Answers keyed by the command that provokes them.
    private let scripted: [String: String]
    /// A knob rather than a simulation: `send` here always reaches the robot, and
    /// this exists only to say which wait a caller is bounding.
    private var open: Bool

    init(replies: [String: String] = [:], isOpen: Bool = true) {
        scripted = replies
        open = isOpen
    }

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return open
    }

    /// The peer connection went away and another is being negotiated in its place.
    func losePeer() {
        lock.lock()
        open = false
        lock.unlock()
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

    /// Whether anyone is reading. Polled rather than slept on, so a loaded runner
    /// cannot turn the wait into a flake.
    var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation != nil
    }

    /// The stream ends — which is the only thing a data channel can say to mean
    /// "nothing more is coming this way".
    func close() {
        lock.lock()
        let listener = continuation
        continuation = nil
        lock.unlock()
        listener?.finish()
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
