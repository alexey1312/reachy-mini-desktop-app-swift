import Foundation
import Network

/// Minimal in-process WebSocket server for transport tests.
/// Accepts connections on an ephemeral port, hands each one to `onConnection`.
final class LocalWebSocketServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalWebSocketServer")

    var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    init(onConnection: @escaping @Sendable (NWConnection) -> Void) throws {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue(label: "LocalWebSocketServer.connection"))
            onConnection(connection)
        }
        listener.start(queue: queue)
    }

    /// Waits until the listener is ready and returns its port.
    func readyPort() async throws -> UInt16 {
        while listener.state != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        return port
    }

    /// `then` runs once the frame is actually on the wire. A test that tears the
    /// connection down straight after the call would otherwise race the send and
    /// drop the very frame it is asserting on.
    static func sendText(_ text: String, over connection: NWConnection, then onSent: (@Sendable () -> Void)? = nil) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(
            content: Data(text.utf8),
            contentContext: context,
            isComplete: true,
            completion: onSent.map { sent in .contentProcessed { _ in sent() } } ?? .idempotent
        )
    }

    /// Fires once the client closes: a WebSocket close frame, or the connection
    /// failing under it. A client that merely stops reading never gets here, which
    /// is exactly the distinction a cancellation test needs to draw.
    static func whenClosed(_ connection: NWConnection, run onClosed: @escaping @Sendable () -> Void) {
        connection.receiveMessage { _, context, _, error in
            let metadata = context?
                .protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if error != nil || metadata?.opcode == .close {
                onClosed()
            } else {
                whenClosed(connection, run: onClosed)
            }
        }
    }

    func stop() {
        listener.cancel()
    }
}

/// A cross-queue flag for a Network.framework callback to raise and a test to
/// poll. Tests wait on conditions, not durations (project rule 7).
final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool {
        lock.withLock { raised }
    }

    func raise() {
        lock.withLock { raised = true }
    }

    /// Polls until raised, or gives up and reports it never was.
    func waitRaised(within budget: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now + budget
        while ContinuousClock.now < deadline {
            if isRaised {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return isRaised
    }
}
