import Foundation
@testable import ReachyKit
import Testing

@Suite("LogStreamClient")
struct LogStreamClientTests {
    @Test("delivers journal lines in order", .timeLimit(.minutes(1)))
    func deliversLines() async throws {
        let server = try LocalWebSocketServer { connection in
            for line in [
                "2026-08-03T10:00:00+0000 reachy daemon[1]: one",
                "2026-08-03T10:00:01+0000 reachy daemon[1]: two",
                "2026-08-03T10:00:02+0000 reachy daemon[1]: three",
            ] {
                LocalWebSocketServer.sendText(line, over: connection)
            }
        }
        defer { server.stop() }
        let port = try await server.readyPort()

        let client = try LogStreamClient(address: RobotAddress(host: "127.0.0.1", port: Int(port)))
        var received: [String] = []
        for await line in client.lines() {
            received.append(line)
            if received.count == 3 {
                break
            }
        }
        #expect(received.count == 3)
        #expect(zip(received, ["one", "two", "three"]).allSatisfy { $0.hasSuffix($1) })
    }
}
