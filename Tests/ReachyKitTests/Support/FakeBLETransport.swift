import Foundation
@testable import ReachyKit

/// Stands in for the robot's GATT service, which is Linux/BlueZ and therefore
/// impossible to simulate — only real hardware speaks it.
///
/// Scripted per command: `readReplies` is what a read of the response characteristic
/// returns, `notifications` what arrives afterwards. A command with no scripted
/// notification models a synchronous reply.
final class FakeBLETransport: BLETransport, @unchecked Sendable {
    struct Script {
        /// What the response characteristic reads back straight after the write.
        var read: String
        /// Delivered as a notification afterwards. Nil for synchronous commands.
        var notify: String?
        /// Skips the notification entirely, so the pump has to fall back to a re-read.
        var dropsNotification = false
    }

    private let lock = NSLock()
    private var scripts: [String: Script] = [:]
    private var writes: [String] = []
    private var overlappingWrites = false
    private var writeInFlight = false
    private var lastRead: String = ""
    private var continuation: AsyncStream<Data>.Continuation?
    private var eventContinuation: AsyncStream<BLETransportEvent>.Continuation?

    var availability: BLEAvailability = .ready
    var discovered: [BLEPeripheralSnapshot] = []
    var maximumWriteLength = 512
    var attributeWriteLength = 512
    var writeError: (any Error)?
    /// Delay inserted inside `write`, so an overlap between two `send` calls is
    /// observable rather than theoretical.
    var writeDelay: Duration = .zero

    init(scripts: [String: Script] = [:]) {
        self.scripts = scripts
    }

    var writtenCommands: [String] {
        lock.withLock { writes }
    }

    var sawOverlappingWrites: Bool {
        lock.withLock { overlappingWrites }
    }

    func script(_ command: String, read: String, notify: String? = nil, dropsNotification: Bool = false) {
        lock.withLock {
            scripts[command] = Script(read: read, notify: notify, dropsNotification: dropsNotification)
        }
    }

    func startScan() throws {}
    func stopScan() {}
    func connect(_: UUID) async throws {}
    func disconnect() {}
    func setNotify(_: Bool, for _: BLECharacteristicID) async throws {}

    func notifications() -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        lock.withLock { self.continuation = continuation }
        return stream
    }

    func events() -> AsyncStream<BLETransportEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BLETransportEvent.self)
        lock.withLock { self.eventContinuation = continuation }
        return stream
    }

    func emit(_ event: BLETransportEvent) {
        lock.withLock { eventContinuation }?.yield(event)
    }

    func write(_ payload: Data, to _: BLECharacteristicID) async throws {
        if let writeError {
            throw writeError
        }
        let command = String(bytes: payload, encoding: .utf8) ?? ""
        lock.withLock {
            if writeInFlight {
                overlappingWrites = true
            }
            writeInFlight = true
            writes.append(command)
        }
        if writeDelay > .zero {
            try? await Task.sleep(for: writeDelay)
        }

        let script = lock.withLock { scripts[command] }
        lock.withLock {
            writeInFlight = false
            lastRead = script?.read ?? "ECHO: \(command)"
        }
        guard let script, let notify = script.notify, !script.dropsNotification else { return }
        // A real notification never lands before the write completes.
        Task { [weak self] in
            guard let self else { return }
            let continuation = lock.withLock { self.continuation }
            lock.withLock { self.lastRead = notify }
            continuation?.yield(Data(notify.utf8))
        }
    }

    /// What the plain status characteristics read back. The response characteristic is
    /// deliberately not covered: whatever the last write left there is the whole point
    /// of the pump.
    var characteristicValues: [BLECharacteristicID: String] = [:]

    var isObservingEvents: Bool {
        lock.withLock { eventContinuation != nil }
    }

    func read(_ characteristic: BLECharacteristicID) async throws -> Data {
        if characteristic != .response, let value = characteristicValues[characteristic] {
            return Data(value.utf8)
        }
        return Data(lock.withLock { lastRead }.utf8)
    }
}
