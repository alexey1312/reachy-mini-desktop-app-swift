import Foundation
@testable import ReachyKit
import Testing

/// The socket alone cannot be trusted to end an install, and the poll alone would
/// deliver the log in 500 ms lumps. This is where the two are reconciled.
@Suite("App job monitor", .timeLimit(.minutes(1)))
struct AppJobMonitorTests {
    /// Generous on purpose: a loaded runner must not turn "the job is still
    /// running" into a timeout (project rule 7).
    private static let configuration = AppJobMonitor.Configuration(
        pollInterval: .milliseconds(5),
        timeout: .seconds(10)
    )

    private func silentSocket() -> AsyncStream<JobLogEvent> {
        AsyncStream { _ in }
    }

    private func socket(_ events: [JobLogEvent]) -> AsyncStream<JobLogEvent> {
        AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    /// Hands out the scripted answers in order, repeating the last one forever.
    private final class Poll: @unchecked Sendable {
        private let answers: [Result<DaemonJob, any Error>]
        private let lock = NSLock()
        private var index = 0

        init(_ answers: [Result<DaemonJob, any Error>]) {
            self.answers = answers
        }

        func next() throws -> DaemonJob {
            let answer = lock.withLock { () -> Result<DaemonJob, any Error> in
                defer { index = min(index + 1, answers.count - 1) }
                return answers[min(index, answers.count - 1)]
            }
            return try answer.get()
        }
    }

    private func collect(
        socket: AsyncStream<JobLogEvent>,
        poll: Poll,
        configuration: AppJobMonitor.Configuration = configuration
    ) async -> [AppJobMonitor.Event] {
        let monitor = AppJobMonitor(
            configuration: configuration,
            logs: { socket },
            job: { try poll.next() }
        )
        var received: [AppJobMonitor.Event] = []
        for await event in monitor.events() {
            received.append(event)
        }
        return received
    }

    private func job(_ status: DaemonJob.Status, _ logs: [String] = []) -> DaemonJob {
        DaemonJob(command: "install", status: status, logs: logs)
    }

    @Test("the socket's own terminal status ends the job")
    func finishesOnSocketStatus() async {
        let events = await collect(
            socket: socket([.line("Collecting reachy-mini"), .status(.done), .closed]),
            poll: Poll([.success(job(.inProgress, ["Collecting reachy-mini"]))])
        )

        #expect(events == [
            .line("Collecting reachy-mini"),
            .status(.done),
            .finished(.succeeded),
        ])
    }

    /// `ws_poll_info` only ever wakes on a *new* log line, so a job that finished
    /// before the socket opened sends nothing at all — for good. Without the poll
    /// running alongside it, the install would sit on its spinner forever.
    @Test("a socket that never says anything still finishes, because the poll does")
    func finishesFromPollingWhenTheSocketIsSilent() async {
        let events = await collect(
            socket: silentSocket(),
            poll: Poll([
                .success(job(.inProgress, ["Collecting reachy-mini"])),
                .success(job(.done, ["Collecting reachy-mini", "Successfully installed"])),
            ])
        )

        #expect(events == [
            .line("Collecting reachy-mini"),
            .status(.inProgress),
            .line("Successfully installed"),
            .status(.done),
            .finished(.succeeded),
        ])
    }

    /// The poll answers with the job's *whole* log every time; the socket has
    /// already delivered the front of it.
    @Test("a line the socket already delivered is not repeated by the poll")
    func doesNotRepeatLines() async {
        let events = await collect(
            socket: socket([.line("Collecting reachy-mini")]),
            poll: Poll([
                .success(job(.done, ["Collecting reachy-mini", "Successfully installed"])),
            ])
        )

        #expect(events.filter { $0 == .line("Collecting reachy-mini") }.count == 1)
        #expect(events.last == .finished(.succeeded))
    }

    /// A failed job is a 200 with `status: failed` — never an HTTP error — and the
    /// reason is only ever the last line the job logged.
    @Test("a failed job carries the reason it failed")
    func reportsFailureReason() async {
        let events = await collect(
            socket: silentSocket(),
            poll: Poll([
                .success(job(.failed, ["Collecting", "Job 'install' failed with error: no matching distribution"])),
            ])
        )

        #expect(events.last == .finished(.failed("Job 'install' failed with error: no matching distribution")))
    }

    /// The job register is in memory. A daemon that restarted mid-install answers
    /// 404 for a job that really did start — which is not the same as a failure,
    /// and the user has to be told to go and look.
    @Test("a job the daemon has forgotten ends as a restart, not a failure")
    func reportsForgottenJob() async {
        let events = await collect(
            socket: silentSocket(),
            poll: Poll([.failure(ReachyKitError.daemonRejected(statusCode: 404))])
        )

        #expect(events == [.finished(.daemonRestarted)])
    }

    /// Same conclusion over the socket: the daemon greets an unknown id with one
    /// JSON frame and hangs up.
    @Test("the socket rejecting the job ends it the same way")
    func reportsRejectedJob() async {
        let events = await collect(
            socket: socket([.rejected("Job ID not found"), .closed]),
            poll: Poll([.failure(ReachyKitError.daemonRejected(statusCode: 404))])
        )

        #expect(events.last == .finished(.daemonRestarted))
    }

    @Test("a job that never ends gives up on its own deadline")
    func timesOut() async {
        let events = await collect(
            socket: silentSocket(),
            poll: Poll([.success(job(.inProgress, []))]),
            configuration: .init(pollInterval: .milliseconds(5), timeout: .milliseconds(200))
        )

        #expect(events == [.status(.inProgress), .finished(.timedOut)])
    }

    /// Whatever happens, a screen gets exactly one ending and the stream closes —
    /// a second outcome would leave an overlay with nothing to dismiss it.
    @Test("there is exactly one outcome, and the stream ends with it")
    func endsExactlyOnce() async {
        let events = await collect(
            socket: socket([.status(.done), .closed]),
            poll: Poll([.success(job(.done, ["Successfully installed"]))])
        )

        let outcomes = events.filter {
            if case .finished = $0 {
                true
            } else {
                false
            }
        }
        #expect(outcomes.count == 1)
        #expect(events.last == .finished(.succeeded))
    }

    /// A transient poll failure is not the end of a job: the network drops a packet
    /// far more often than the daemon forgets a job.
    @Test("a poll that fails once keeps going")
    func survivesATransientPollFailure() async {
        let events = await collect(
            socket: silentSocket(),
            poll: Poll([
                .failure(URLError(.timedOut)),
                .success(job(.done, ["Successfully installed"])),
            ])
        )

        #expect(events.last == .finished(.succeeded))
    }
}
