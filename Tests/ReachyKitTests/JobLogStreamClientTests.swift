import Foundation
import Network
@testable import ReachyKit
import Testing

/// The daemon sends every new line twice over this socket — once as its own text
/// frame, then again inside a `JobInfo` JSON frame — and it dies mid-job by design.
/// Both are easy to get wrong in ways that look like a working stream.
///
/// One suite for both sockets because there is one implementation behind them:
/// `/update/ws/logs` and `/api/apps/ws/apps-manager/{job_id}` are two routes onto
/// the same `bg_job_register.ws_poll_info`.
@Suite("JobLogStreamClient")
struct JobLogStreamClientTests {
    private func collect(
        from server: LocalWebSocketServer,
        jobID: String = "job-1",
        until isDone: @escaping ([JobLogEvent]) -> Bool
    ) async throws -> [JobLogEvent] {
        let port = try await server.readyPort()
        let client = try JobLogStreamClient.daemonUpdate(
            address: RobotAddress(host: "127.0.0.1", port: Int(port)),
            jobID: jobID
        )
        var received: [JobLogEvent] = []
        for await event in client.events() {
            received.append(event)
            if isDone(received) {
                break
            }
        }
        return received
    }

    @Test("a JobInfo frame contributes its status only — its logs repeat lines already sent", .timeLimit(.minutes(1)))
    func doesNotDuplicateLinesFromStatusFrames() async throws {
        let statusFrame = """
        {"command": "update_reachy_mini", "status": "in_progress",
         "logs": ["Collecting reachy-mini", "Installing collected packages"]}
        """
        let server = try LocalWebSocketServer { connection in
            LocalWebSocketServer.sendText("Collecting reachy-mini", over: connection)
            LocalWebSocketServer.sendText("Installing collected packages", over: connection)
            LocalWebSocketServer.sendText(statusFrame, over: connection)
        }
        defer { server.stop() }

        let received = try await collect(from: server) { $0.contains(.status(.inProgress)) }

        #expect(received == [
            .line("Collecting reachy-mini"),
            .line("Installing collected packages"),
            .status(.inProgress),
        ])
    }

    @Test("an unknown job is rejected on the first frame and ends the stream", .timeLimit(.minutes(1)))
    func reportsUnknownJob() async throws {
        let server = try LocalWebSocketServer { connection in
            LocalWebSocketServer.sendText(#"{"error": "Job ID not found"}"#, over: connection)
        }
        defer { server.stop() }

        let received = try await collect(from: server, jobID: "nope") { $0.contains(.closed) }

        #expect(received == [.rejected("Job ID not found"), .closed])
    }

    @Test("the socket dropping mid-job closes the stream once, without reconnecting", .timeLimit(.minutes(1)))
    func closesOnceWhenTheDaemonRestarts() async throws {
        let server = try LocalWebSocketServer { connection in
            // The real daemon dies right here: `systemctl restart` kills the process
            // before the terminal `done` frame is ever written.
            LocalWebSocketServer.sendText("Successfully installed reachy-mini", over: connection) {
                connection.cancel()
            }
        }
        defer { server.stop() }

        let received = try await collect(from: server) { $0.contains(.closed) }

        #expect(received == [.line("Successfully installed reachy-mini"), .closed])
    }

    @Test("a log line that happens to be JSON is still a log line")
    func treatsUnrecognisedJSONAsALine() {
        #expect(JobLogStreamClient.events(in: #"{"pip": "noise"}"#) == [.line(#"{"pip": "noise"}"#)])
        #expect(JobLogStreamClient.events(in: "  ") == [.line("  ")])
    }

    /// The two routes disagree about where the job id goes, and neither sits under
    /// the other's prefix: `/update/*` is mounted at the app root, the apps socket
    /// under `/api`.
    @Test("each route addresses its job the way its own daemon route expects")
    func buildsBothURLs() throws {
        let address = RobotAddress(host: "10.42.0.1")

        #expect(try JobLogStreamClient.daemonUpdate(address: address, jobID: "job-1").url
            .absoluteString == "ws://10.42.0.1:8000/update/ws/logs?job_id=job-1")
        #expect(try JobLogStreamClient.appsManager(address: address, jobID: "job-1").url
            .absoluteString == "ws://10.42.0.1:8000/api/apps/ws/apps-manager/job-1")
    }

    /// An app install ends with a status frame rather than a dead socket — the
    /// daemon stays up — so a terminal status has to arrive intact.
    @Test("an install that finishes reports its terminal status", .timeLimit(.minutes(1)))
    func reportsTerminalStatusOfAnAppJob() async throws {
        let server = try LocalWebSocketServer { connection in
            LocalWebSocketServer.sendText("Job 'install' completed successfully", over: connection)
            LocalWebSocketServer.sendText(
                #"{"command": "install", "status": "done", "logs": ["Job 'install' completed successfully"]}"#,
                over: connection
            )
        }
        defer { server.stop() }

        let port = try await server.readyPort()
        let client = try JobLogStreamClient.appsManager(
            address: RobotAddress(host: "127.0.0.1", port: Int(port)),
            jobID: "job-1"
        )
        var received: [JobLogEvent] = []
        for await event in client.events() {
            received.append(event)
            if event == .status(.done) {
                break
            }
        }

        #expect(received == [.line("Job 'install' completed successfully"), .status(.done)])
    }
}
