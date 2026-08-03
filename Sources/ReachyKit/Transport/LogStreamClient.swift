import Foundation

/// Streams daemon log lines from `ws://…/logs/ws/daemon`.
///
/// The daemon tails `journalctl -u reachy-mini-daemon` — plain text lines
/// (short-iso). The router is mounted at the app ROOT (not under `/api`) and
/// only with `--wireless-version`: real robot only, the simulator rejects the
/// upgrade with HTTP 403 (verified against daemon main.py and a live sim).
/// Same reconnect-with-backoff shape as `StateStreamClient`.
public struct LogStreamClient: Sendable {
    public static let path = "/logs/ws/daemon"

    private let url: URL
    private let session: URLSession

    public init(address: RobotAddress, session: URLSession = .shared) throws {
        guard let url = address.webSocketURL(path: Self.path) else {
            throw ReachyKitError.invalidAddress(address)
        }
        self.url = url
        self.session = session
    }

    /// Log lines; never throws, ends only on cancellation. Reconnects with backoff.
    public func lines() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: String.self,
            bufferingPolicy: .bufferingNewest(500)
        )
        let task = Task { [url, session] in
            var backoff = Duration.milliseconds(500)
            while !Task.isCancelled {
                let socket = session.webSocketTask(with: url)
                socket.resume()
                do {
                    while true {
                        let message = try await socket.receive()
                        if case let .string(text) = message {
                            continuation.yield(text)
                            backoff = .milliseconds(500)
                        }
                    }
                } catch {
                    socket.cancel(with: .goingAway, reason: nil)
                }
                if Task.isCancelled {
                    break
                }
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, .seconds(15))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
