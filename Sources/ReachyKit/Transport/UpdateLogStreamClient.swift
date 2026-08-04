import Foundation

/// One message from `ws://…/update/ws/logs?job_id=…`.
public enum UpdateLogEvent: Sendable, Equatable {
    case line(String)
    case status(DaemonUpdateJob.Status)
    /// The daemon does not know this job — always the first and only frame.
    case rejected(String)
    /// The socket ended. This, not a `done` status, is what completion looks like:
    /// the update finishes by restarting the daemon, which kills the process before
    /// the terminal frame is ever written.
    case closed
}

/// Streams one update job's log from `ws://…/update/ws/logs?job_id=…`.
///
/// Two deliberate differences from `LogStreamClient`:
///
/// - **No reconnect.** The job ends with `systemctl restart reachy-mini-daemon`, and
///   the in-memory job register dies with the process. Reconnecting would hammer a
///   daemon that is rebooting and could never find the job again afterwards.
/// - **Two frame shapes on one socket.** `bg_job_register.ws_poll_info` sends each new
///   line as its own text frame and *then* a `JobInfo` JSON frame repeating those same
///   lines. Decoding both would duplicate every line, so a frame that parses as JSON
///   contributes only its status.
public struct UpdateLogStreamClient: Sendable {
    public static let path = "/update/ws/logs"

    private let url: URL
    private let session: URLSession

    public init(address: RobotAddress, jobID: String, session: URLSession = .shared) throws {
        guard let url = address.webSocketURL(
            path: Self.path,
            queryItems: [URLQueryItem(name: "job_id", value: jobID)]
        ) else {
            throw ReachyKitError.invalidAddress(address)
        }
        self.url = url
        self.session = session
    }

    /// Ends with exactly one `.closed`, whether the daemon finished, restarted or died.
    public func events() -> AsyncStream<UpdateLogEvent> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: UpdateLogEvent.self,
            bufferingPolicy: .bufferingNewest(1000)
        )
        let task = Task { [url, session] in
            let socket = session.webSocketTask(with: url)
            socket.resume()
            defer {
                socket.cancel(with: .goingAway, reason: nil)
                continuation.yield(.closed)
                continuation.finish()
            }
            while !Task.isCancelled {
                guard let message = try? await socket.receive() else { return }
                guard case let .string(text) = message else { continue }
                for event in Self.events(in: text) {
                    continuation.yield(event)
                    if case .rejected = event {
                        return
                    }
                }
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// A frame is either a raw log line or one of the two JSON shapes the daemon sends.
    static func events(in frame: String) -> [UpdateLogEvent] {
        struct Rejection: Decodable {
            let error: String
        }
        guard let data = frame.data(using: .utf8) else {
            return [.line(frame)]
        }
        if let rejection = try? JSONDecoder().decode(Rejection.self, from: data) {
            return [.rejected(rejection.error)]
        }
        if let job = try? JSONDecoder.reachyDaemon.decode(DaemonUpdateJob.self, from: data) {
            // `job.logs` repeats lines already delivered as their own frames.
            return [.status(job.status)]
        }
        return [.line(frame)]
    }
}
