import Foundation
@testable import ReachyKit
import Testing

@Suite("StateStreamClient")
struct StateStreamClientTests {
    /// The client must survive a server-side connection drop: after the first
    /// connection dies, it reconnects with backoff and keeps delivering states.
    /// This encodes the core Phase 0 requirement — a robot rebooting or Wi-Fi
    /// blipping must not kill the stream.
    @Test("reconnects after the server drops the connection", .timeLimit(.minutes(1)))
    func reconnectsAfterDrop() async throws {
        let payload = #"{"body_yaw": 0.5}"#

        // Each accepted connection: send one state, then slam the connection shut.
        let server = try LocalWebSocketServer { connection in
            LocalWebSocketServer.sendText(payload, over: connection)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                connection.forceCancel()
            }
        }
        defer { server.stop() }
        let port = try await server.readyPort()

        var configuration = StateStreamClient.Configuration()
        configuration.initialBackoff = .milliseconds(50)
        configuration.maxBackoff = .milliseconds(200)
        let client = try StateStreamClient(
            address: RobotAddress(host: "127.0.0.1", port: Int(port)),
            configuration: configuration
        )

        // Receiving 3 states requires surviving at least 2 reconnects.
        var received = 0
        for await state in client.states() {
            #expect(state.bodyYaw == 0.5)
            received += 1
            if received == 3 {
                break
            }
        }
        #expect(received == 3)
    }

    @Test("malformed frame is counted and the following frame still decodes", .timeLimit(.minutes(1)))
    func malformedFrameDoesNotKillStream() async throws {
        let server = try LocalWebSocketServer { connection in
            LocalWebSocketServer.sendText(#"{"body_yaw":"not-a-number"}"#, over: connection)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                LocalWebSocketServer.sendText(#"{"body_yaw":0.75}"#, over: connection)
            }
        }
        defer { server.stop() }
        let port = try await server.readyPort()
        let client = try StateStreamClient(address: .init(host: "127.0.0.1", port: Int(port)))

        var finalDiagnostics = StateStreamDiagnostics()
        var decodedYaw: Double?
        for await update in client.updates() {
            finalDiagnostics = update.diagnostics
            if let state = update.state {
                decodedYaw = state.bodyYaw
                break
            }
        }

        #expect(decodedYaw == 0.75)
        #expect(finalDiagnostics.receivedFrames == 2)
        #expect(finalDiagnostics.decodedFrames == 1)
        #expect(finalDiagnostics.decodeFailures == 1)
        #expect(finalDiagnostics.lastFailureDescription != nil)
        #expect(finalDiagnostics.lastFailureAt != nil)
    }

    @Test("invalid host throws invalidAddress")
    func invalidAddress() {
        #expect(throws: ReachyKitError.self) {
            _ = try StateStreamClient(address: RobotAddress(host: ""))
        }
    }
}
