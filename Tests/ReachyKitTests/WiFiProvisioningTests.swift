import Foundation
@testable import ReachyKit
import Testing

@Suite("Wi-Fi scan replies")
struct WiFiScanResultTests {
    @Test("a whole reply reads as itself")
    func readsCompleteReplies() {
        #expect(WiFiScanResult.networks(in: #"["Home","Cafe Wi-Fi"]"#) == ["Home", "Cafe Wi-Fi"])
    }

    /// The robot caps the reply at 180 bytes without saying so, so this is what an
    /// ordinary scan in a busy building looks like — not a corrupted one.
    @Test("a reply cut mid-name keeps every name that finished")
    func salvagesTruncatedReplies() {
        #expect(WiFiScanResult.networks(in: #"["Home","Cafe Wi-Fi","Offi"#) == ["Home", "Cafe Wi-Fi"])
    }

    @Test("hidden networks and repeats are not offered")
    func dropsEmptyAndDuplicateNames() {
        #expect(WiFiScanResult.networks(in: #"["Home","","Home","Cafe"]"#) == ["Home", "Cafe"])
    }

    @Test("a reply with nothing usable in it is empty, not a failure")
    func toleratesGarbage() {
        #expect(WiFiScanResult.networks(in: "").isEmpty)
        #expect(WiFiScanResult.networks(in: "[").isEmpty)
    }
}

@Suite("Wi-Fi provisioning")
struct WiFiProvisioningTests {
    @Test("a robot that accepts the first payload is asked for one key", .timeLimit(.minutes(1)))
    func sealsUnderOneKeyWhenAccepted() async throws {
        let transport = FakeProvisioningTransport()

        try await WiFiProvisioning.join(ssid: "Home", password: "hunter2", pin: "AB12C", using: transport)

        #expect(transport.issuedKeys.count == 1)
        #expect(transport.sealedPayloads.count == 1)
    }

    /// The robot rotates its keypair every 600 s and reports a stale `kid` with the very
    /// same error as a wrong PIN. Retrying once under a fresh key is what separates them.
    @Test("a refusal buys exactly one retry, under a new key", .timeLimit(.minutes(1)))
    func retriesOnceWithAFreshKey() async throws {
        let transport = FakeProvisioningTransport()
        transport.refusesFirst = 1

        try await WiFiProvisioning.join(ssid: "Home", password: "hunter2", pin: "AB12C", using: transport)

        #expect(transport.issuedKeys.map(\.kid) == ["key-0", "key-1"])
        let accepted = try #require(transport.sealedPayloads.first)
        #expect(accepted.kid == "key-1")
    }

    @Test("a second refusal is the PIN, and is not retried again", .timeLimit(.minutes(1)))
    func stopsAfterTheRetry() async throws {
        let transport = FakeProvisioningTransport()
        transport.refusesFirst = 2

        await #expect(throws: BLECommandError.badCredentials) {
            try await WiFiProvisioning.join(ssid: "Home", password: "hunter2", pin: "AB12C", using: transport)
        }
        #expect(transport.issuedKeys.count == 2)
        #expect(transport.sealedPayloads.isEmpty)
    }

    @Test("the join is reported once the robot says it is on the network", .timeLimit(.minutes(1)))
    func reportsAJoin() async throws {
        let transport = FakeProvisioningTransport()
        transport.connectsAfterReads = 3

        let outcome = try await WiFiProvisioning.awaitJoin(
            using: transport,
            timeout: .seconds(30),
            pollInterval: .milliseconds(1)
        )

        guard case let .joined(status) = outcome else {
            Issue.record("expected a join, got \(outcome)")
            return
        }
        #expect(status.hasJoined("Home"))
    }

    /// A robot that failed to join goes back to its own access point, so the last status
    /// is what the screen needs to say what happened rather than implying a brick.
    @Test("giving up reports where the robot ended up", .timeLimit(.minutes(1)))
    func reportsWhereItGaveUp() async throws {
        let transport = FakeProvisioningTransport()

        let outcome = try await WiFiProvisioning.awaitJoin(
            using: transport,
            timeout: .zero,
            pollInterval: .milliseconds(1)
        )

        #expect(outcome == .gaveUp(last: WiFiStatus(mode: .hotspot, connected: nil)))
    }
}
