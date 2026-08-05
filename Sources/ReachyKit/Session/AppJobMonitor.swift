import Foundation

/// Follows one app install, removal or update to its end.
///
/// Neither of the daemon's two ways of reporting a job is sufficient alone:
///
/// - the **socket** delivers each log line the moment it is written, but only ever
///   wakes on a *new* line. A job that finished before the socket opened sends
///   nothing at all, ever — the stream simply hangs;
/// - the **poll** always answers, but in `pollInterval` lumps, and its 404 is the
///   only way to learn that the daemon restarted and took the job register with it.
///
/// So both run, and this reconciles them. Both sources report the job's log from
/// its first line (`ws_poll_info` starts its cursor at zero too), which is what
/// makes a single "lines emitted" cursor enough to keep either from repeating the
/// other.
public struct AppJobMonitor: Sendable {
    public struct Configuration: Sendable {
        public var pollInterval: Duration
        /// Upstream's budgets, which are what the robot was tested against.
        public var timeout: Duration

        public init(pollInterval: Duration = .milliseconds(500), timeout: Duration = .seconds(60)) {
            self.pollInterval = pollInterval
            self.timeout = timeout
        }

        public static let install = Self(timeout: .seconds(60))
        public static let removal = Self(timeout: .seconds(90))
        public static let update = Self(timeout: .seconds(90))
    }

    public enum Outcome: Sendable, Equatable {
        case succeeded
        /// The daemon reports a failed job with a 200 and `status: failed` — never
        /// as an HTTP error. The reason is the last line the job logged.
        case failed(String?)
        /// The job register is in memory: a daemon that restarted mid-job answers
        /// 404 for work that really did start. Neither success nor failure, and the
        /// only honest thing to do is say so and re-read the installed list.
        case daemonRestarted
        case timedOut
    }

    public enum Event: Sendable, Equatable {
        case line(String)
        case status(DaemonJob.Status)
        /// Always the last event, and there is exactly one.
        case finished(Outcome)
    }

    private let configuration: Configuration
    private let logs: @Sendable () -> AsyncStream<JobLogEvent>
    private let job: @Sendable () async throws -> DaemonJob

    /// Both sources are injected rather than built here: the session owns the
    /// address and the client, and a test has no business standing up a socket.
    public init(
        configuration: Configuration = .install,
        logs: @escaping @Sendable () -> AsyncStream<JobLogEvent>,
        job: @escaping @Sendable () async throws -> DaemonJob
    ) {
        self.configuration = configuration
        self.logs = logs
        self.job = job
    }

    public func events() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Event.self,
            bufferingPolicy: .bufferingNewest(1000)
        )
        let task = Task { [configuration, logs, job] in
            let coordinator = Coordinator(continuation: continuation)
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await coordinator.follow(logs()) }
                group.addTask { await coordinator.poll(job, every: configuration.pollInterval) }
                group.addTask {
                    try? await Task.sleep(for: configuration.timeout)
                    await coordinator.finish(.timedOut)
                }
                for await _ in group where await coordinator.hasFinished {
                    break
                }
                group.cancelAll()
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private actor Coordinator {
        private let continuation: AsyncStream<Event>.Continuation
        /// How much of the job's log has reached the caller. Both sources index
        /// into the same list, so this is what keeps them from doubling it up.
        private var emittedLines = 0
        private var lastLine: String?
        private var lastStatus: DaemonJob.Status?
        private var isFinished = false

        init(continuation: AsyncStream<Event>.Continuation) {
            self.continuation = continuation
        }

        var hasFinished: Bool {
            isFinished
        }

        func follow(_ stream: AsyncStream<JobLogEvent>) async {
            var received = 0
            for await event in stream {
                guard !isFinished else { return }
                switch event {
                case let .line(text):
                    deliver(line: text, at: received)
                    received += 1
                case let .status(status):
                    deliver(status)
                case .rejected:
                    // The daemon greets an unknown job id with one frame and hangs
                    // up. Same conclusion as the poll's 404.
                    finish(.daemonRestarted)
                    return
                case .closed:
                    // Not an outcome on its own: an app job leaves the daemon
                    // standing, so the poll can still tell us how it ended.
                    return
                }
            }
        }

        func poll(_ job: @Sendable () async throws -> DaemonJob, every interval: Duration) async {
            while !Task.isCancelled, !isFinished {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, !isFinished else { return }
                do {
                    let info = try await job()
                    guard !isFinished else { return }
                    deliver(logs: info.logs)
                    deliver(info.status)
                } catch ReachyKitError.daemonRejected(statusCode: 404) {
                    finish(.daemonRestarted)
                    return
                } catch {
                    // A dropped packet is not a lost job — keep asking.
                }
            }
        }

        func finish(_ outcome: Outcome) {
            guard !isFinished else { return }
            isFinished = true
            continuation.yield(.finished(outcome))
            continuation.finish()
        }

        private func deliver(logs: [String]) {
            guard logs.count > emittedLines else { return }
            for line in logs[emittedLines...] {
                continuation.yield(.line(line))
                lastLine = line
            }
            emittedLines = logs.count
        }

        private func deliver(line: String, at index: Int) {
            guard index >= emittedLines else { return }
            continuation.yield(.line(line))
            lastLine = line
            emittedLines = index + 1
        }

        private func deliver(_ status: DaemonJob.Status) {
            guard status != lastStatus else { return }
            lastStatus = status
            continuation.yield(.status(status))
            switch status {
            case .done: finish(.succeeded)
            case .failed: finish(.failed(lastLine))
            default: break
            }
        }
    }
}
