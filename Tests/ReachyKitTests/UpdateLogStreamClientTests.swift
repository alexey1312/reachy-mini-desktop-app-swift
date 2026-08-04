import Foundation
import Network
@testable import ReachyKit
import Testing

/// The daemon sends every new line twice over this socket — once as its own text
/// frame, then again inside a `JobInfo` JSON frame — and it dies mid-job by design.
/// Both are easy to get wrong in ways that look like a working stream.
@Suite("UpdateLogStreamClient")
struct UpdateLogStreamClientTests {
    private func collect(
        from server: LocalWebSocketServer,
        jobID: String = "job-1",
        until isDone: @escaping ([UpdateLogEvent]) -> Bool
    ) async throws -> [UpdateLogEvent] {
        let port = try await server.readyPort()
        let client = try UpdateLogStreamClient(
            address: RobotAddress(host: "127.0.0.1", port: Int(port)),
            jobID: jobID
        )
        var received: [UpdateLogEvent] = []
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
        #expect(UpdateLogStreamClient.events(in: #"{"pip": "noise"}"#) == [.line(#"{"pip": "noise"}"#)])
        #expect(UpdateLogStreamClient.events(in: "  ") == [.line("  ")])
    }
}
