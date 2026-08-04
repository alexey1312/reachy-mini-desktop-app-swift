import Foundation

/// Sends one command at a time and returns its real reply.
///
/// **The reply arrives two different ways and upstream's own documentation gets this
/// wrong.** `CommandCharacteristic.WriteValue` assigns the response characteristic's
/// value directly, without notifying, so synchronous commands — `PING`, `STATUS`,
/// `PIN_…`, `JOURNAL_*` — answer on a *read* and never notify. Only commands proxied
/// to the daemon go through `_emit_response`, and those answer `OK: working`
/// immediately and deliver the real result as a notification later.
///
/// So the sequence is: write, read, and only await a notification if the read was the
/// ack. Awaiting a notification unconditionally hangs forever on a `PING`.
///
/// Write-with-response is what makes the read safe: BlueZ acknowledges the ATT write
/// only after its handler returns, by which point the value is already set.
public actor BLECommandPump {
    private let transport: any BLETransport
    /// Actors are reentrant, so serialisation has to be built rather than assumed:
    /// the single response characteristic carries no correlation id, and two commands
    /// in flight would race for the same reply.
    private var tail: Task<Void, Never>?

    public init(transport: any BLETransport) {
        self.transport = transport
    }

    /// Subscribes to the response characteristic. Must run before any proxied command,
    /// and again after every reconnect — the robot resets its state on disconnect.
    public func prepare() async throws {
        try await transport.setNotify(true, for: .response)
    }

    public func send(_ command: BLECommand) async throws -> BLEReply {
        try await serialized { [self, transport] in
            let payload = command.data
            let limit = transport.maximumWriteLength
            guard payload.count <= limit else {
                throw BLETransportError.payloadTooLong(bytes: payload.count, limit: limit)
            }

            guard command.repliesToWrite else {
                // `CMD_*` crashes the robot's reply encoder on success, so the write
                // itself reporting an error says nothing about whether it ran.
                try? await transport.write(payload, to: .command)
                return .ok("dispatched")
            }

            // Started before the write so a fast notification cannot land in the gap.
            let notifications = transport.notifications()
            try await transport.write(payload, to: .command)

            let immediate = try await BLEResponseParser.parse(transport.read(.response))
            guard immediate.isWorkingAck else {
                return immediate
            }
            return try await awaitResult(on: notifications, timeout: command.timeout)
        }
    }

    /// The robot sets the response value *before* checking whether anyone subscribed,
    /// so a notification lost to a resubscribe or a dropped packet is still recoverable
    /// by reading the characteristic once the wait expires.
    private func awaitResult(on notifications: AsyncStream<Data>, timeout: Duration) async throws -> BLEReply {
        let notified = Task { () -> BLEReply? in
            for await data in notifications {
                let reply = BLEResponseParser.parse(data)
                if !reply.isWorkingAck {
                    return reply
                }
            }
            return nil
        }
        let expiry = Task {
            try? await Task.sleep(for: timeout)
            notified.cancel()
        }
        defer { expiry.cancel() }

        if let reply = await notified.value {
            return reply
        }
        let recovered = try await BLEResponseParser.parse(transport.read(.response))
        guard !recovered.isWorkingAck else {
            throw BLETransportError.timedOut
        }
        return recovered
    }

    private func serialized<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task { () -> T in
            await previous?.value
            return try await work()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
