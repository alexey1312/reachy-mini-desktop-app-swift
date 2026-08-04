import Foundation
@testable import ReachyKit
import Testing

/// The robot answers on two different channels depending on the command, and upstream's
/// own documentation describes only one of them. Getting this wrong does not produce a
/// wrong answer — it produces a client that hangs forever on `PING`.
@Suite("BLECommandPump")
struct BLECommandPumpTests {
    @Test(
        "a synchronous command answers on the read and never waits for a notification",
        .timeLimit(.minutes(1))
    )
    func doesNotAwaitNotificationsForSyncCommands() async throws {
        // No notification is scripted at all: the robot's `WriteValue` sets the read
        // value directly and never calls `send_notification` for these.
        let transport = FakeBLETransport()
        transport.script("PING", read: "PONG")
        let pump = BLECommandPump(transport: transport)

        #expect(try await pump.send(.ping) == .pong)
    }

    @Test(
        "a proxied command skips its ack and returns the notification that follows",
        .timeLimit(.minutes(1))
    )
    func awaitsTheRealResultAfterTheAck() async throws {
        let transport = FakeBLETransport()
        transport.script("WIFI_SCAN", read: BLEReply.workingAck, notify: #"["Home","Cafe"]"#)
        let pump = BLECommandPump(transport: transport)

        #expect(try await pump.send(.wifiScan) == .payload(#"["Home","Cafe"]"#))
    }

    @Test("only a literal working ack is skipped — a real OK is the answer", .timeLimit(.minutes(1)))
    func treatsOtherOKRepliesAsResults() async throws {
        let transport = FakeBLETransport()
        transport.script("PIN_12345", read: "OK: Connected")
        let pump = BLECommandPump(transport: transport)

        #expect(try await pump.send(.authenticate(pin: "12345")) == .ok("Connected"))
    }

    @Test(
        "a lost notification is recovered by re-reading, which the robot leaves valid",
        .timeLimit(.minutes(1))
    )
    func fallsBackToReadingWhenTheNotificationIsLost() async throws {
        let transport = FakeBLETransport()
        transport.script(
            "WIFI_KEYEX",
            read: BLEReply.workingAck,
            notify: #"{"kid":"abc","pk":"key","alg":"x25519-hkdf-sha256-aesgcm"}"#,
            dropsNotification: true
        )
        let pump = BLECommandPump(transport: transport)

        // The value the robot never managed to push is still readable.
        transport.script("WIFI_KEYEX", read: BLEReply.workingAck, notify: nil)
        let reply = try await pump.send(.wifiStatus)

        #expect(reply == .echo("WIFI_STATUS"))
    }

    @Test(
        "commands are serialised — one response characteristic carries no correlation id",
        .timeLimit(.minutes(1))
    )
    func serialisesConcurrentSends() async throws {
        let transport = FakeBLETransport()
        transport.writeDelay = .milliseconds(30)
        transport.script("PING", read: "PONG")
        transport.script("STATUS", read: "OK: System running")
        let pump = BLECommandPump(transport: transport)

        async let first = pump.send(.ping)
        async let second = pump.send(.status)
        _ = try await (first, second)

        #expect(transport.sawOverlappingWrites == false)
        #expect(transport.writtenCommands.count == 2)
    }

    @Test("a script command is dispatched and its write error ignored", .timeLimit(.minutes(1)))
    func swallowsTheWriteErrorOnScripts() async throws {
        let transport = FakeBLETransport()
        // The robot really does fail the write after running the script.
        transport.writeError = BLETransportError.timedOut
        let pump = BLECommandPump(transport: transport)

        let reply = try await pump.send(.runScript("RESTART_DAEMON"))

        #expect(reply == .ok("dispatched"))
    }

    @Test(
        "a payload larger than one ATT write is refused rather than silently fragmented",
        .timeLimit(.minutes(1))
    )
    func refusesAnOversizedPayload() async {
        let transport = FakeBLETransport()
        transport.maximumWriteLength = 182
        let pump = BLECommandPump(transport: transport)
        let json = String(repeating: "x", count: 260)

        await #expect(throws: BLETransportError.payloadTooLong(bytes: 260 + 17, limit: 182)) {
            _ = try await pump.send(.wifiConnectSealed(json: json))
        }
    }

    @Test(
        "an error reply is parsed rather than thrown, so the UI can act on it",
        .timeLimit(.minutes(1))
    )
    func returnsErrorRepliesAsValues() async throws {
        let transport = FakeBLETransport()
        transport.script("WIFI_SCAN", read: BLEReply.workingAck, notify: "ERROR: Busy")
        let pump = BLECommandPump(transport: transport)

        #expect(try await pump.send(.wifiScan) == .failure(.busy))
    }
}
