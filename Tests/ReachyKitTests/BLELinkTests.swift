import Foundation
@testable import ReachyKit
import Testing

@MainActor
private func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0 ..< 1000 {
        if condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("\(what) never happened")
}

@MainActor
@Suite("BLE link")
struct BLELinkTests {
    private static func robot() -> FakeBLETransport {
        let transport = FakeBLETransport()
        transport.characteristicValues = [
            .hardwareID: "a1b2c3d4e5f60718",
            .networkStatus: "HOTSPOT [wlan0] 10.42.0.1",
        ]
        return transport
    }

    /// The hardware id is the join key between the robot just provisioned and the one
    /// that shows up on the LAN a minute later, so connecting has to collect it.
    @Test("connecting collects the identity and where the robot currently is", .timeLimit(.minutes(1)))
    func collectsIdentityOnConnect() async {
        let session = BLELink(transport: Self.robot())

        let connected = await session.connect(to: UUID())

        #expect(connected)
        #expect(session.phase == .connected)
        #expect(session.hardwareID == "a1b2c3d4e5f60718")
        #expect(session.networkStatus?.mode == .hotspot)
        #expect(session.robotAddress == "10.42.0.1")
    }

    @Test("a wrong PIN spends one of the three free attempts", .timeLimit(.minutes(1)))
    func countsWrongPins() async {
        let transport = Self.robot()
        transport.script("PIN_00000", read: "ERROR: Incorrect PIN")
        let session = BLELink(transport: transport)

        let accepted = await session.authenticate("00000")

        #expect(accepted == false)
        #expect(session.pin.attemptsBeforeLockout == 2)
        #expect(session.pin.isAuthenticated() == false)
    }

    /// The throttle is global to the robot and may already have been advanced by another
    /// phone, so its own figure wins over anything counted here. While it runs the robot
    /// does not even compare the PIN, which is why the next attempt is not worth sending.
    @Test("the robot's own lockout is believed and stops the next attempt", .timeLimit(.minutes(1)))
    func honoursTheReportedLockout() async {
        let transport = Self.robot()
        transport.script("PIN_00000", read: "ERROR: Too many attempts. Try again in 40s.")
        let session = BLELink(transport: transport)

        _ = await session.authenticate("00000")
        #expect(session.pin.lockoutRemaining() != nil)

        let sent = transport.writtenCommands.count
        let retried = await session.authenticate("AB12C")

        #expect(retried == false)
        #expect(transport.writtenCommands.count == sent)
    }

    @Test("a dropped link takes the PIN with it", .timeLimit(.minutes(1)))
    func losesThePinOnDisconnect() async throws {
        let transport = Self.robot()
        transport.script("PIN_AB12C", read: "OK: Connected")
        let session = BLELink(transport: transport)
        _ = await session.connect(to: UUID())
        _ = await session.authenticate("AB12C")
        #expect(session.pin.isAuthenticated())

        try await waitUntil("the session subscribes") { transport.isObservingEvents }
        transport.emit(.disconnected(reason: "The robot went out of range."))
        try await waitUntil("the drop is noticed") { session.phase != .connected }

        #expect(session.pin.isAuthenticated() == false)
        // Nothing can be sealed without the PIN, so this must refuse rather than send a
        // payload the robot would reject.
        await #expect(throws: BLECommandError.notAuthenticated) {
            _ = try await session.join(ssid: "Home", password: "hunter2")
        }
    }

    /// A scan in a busy building comes back cut mid-name. The names that survived are
    /// still worth offering — and the ones that did not are why the screen also needs a
    /// manual entry row.
    @Test("a scan cut short still fills the list", .timeLimit(.minutes(1)))
    func acceptsTruncatedScans() async {
        let transport = Self.robot()
        transport.script("WIFI_SCAN", read: BLEReply.workingAck, notify: #"["Home","Cafe","Offi"#)
        let session = BLELink(transport: transport)

        let scanned = await session.refreshNetworks()

        #expect(scanned)
        #expect(session.networks == ["Home", "Cafe"])
    }
}
