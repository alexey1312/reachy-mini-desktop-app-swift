import CoreBluetooth
import Foundation
@testable import ReachyKit
import Testing

/// The adapter needs a radio and a Linux robot, so what is checked here are the two
/// rules that carry a decision rather than a CoreBluetooth call: what the user is told
/// when Bluetooth cannot be used, and the order robots are offered in.
@Suite("CoreBluetoothTransport")
struct CoreBluetoothTransportTests {
    private static func robot(_ id: String, name: String = "ReachyMini", rssi: Int) -> BLEPeripheralSnapshot {
        BLEPeripheralSnapshot(id: UUID(uuidString: id)!, name: name, rssi: rssi)
    }

    private static let near = "00000000-0000-0000-0000-0000000000AA"
    private static let far = "00000000-0000-0000-0000-0000000000BB"

    @Test("every manager state maps to something the screen can explain")
    func mapsManagerStates() {
        #expect(CoreBluetoothTransport.availability(for: .poweredOn) == .ready)
        #expect(CoreBluetoothTransport.availability(for: .poweredOff) == .poweredOff)
        #expect(CoreBluetoothTransport.availability(for: .unauthorized) == .unauthorized)
        // What every iOS Simulator run reports, so it needs a screen of its own.
        #expect(CoreBluetoothTransport.availability(for: .unsupported) == .unsupported)
        // Resetting is temporary, so it must not look like a permanent refusal.
        #expect(CoreBluetoothTransport.availability(for: .resetting) == .unknown)
        #expect(CoreBluetoothTransport.availability(for: .unknown) == .unknown)
    }

    @Test("a fresh sighting replaces the earlier reading rather than duplicating it")
    func replacesRepeatSightings() throws {
        let list = CoreBluetoothTransport.merging(Self.robot(Self.near, rssi: -80), into: [])
        let updated = CoreBluetoothTransport.merging(Self.robot(Self.near, rssi: -45), into: list)

        #expect(try updated.map(\.id) == [#require(UUID(uuidString: Self.near))])
        #expect(updated.first?.rssi == -45)
    }

    @Test("the strongest signal is offered first")
    func ordersByStrength() {
        var list = CoreBluetoothTransport.merging(Self.robot(Self.far, rssi: -88), into: [])
        list = CoreBluetoothTransport.merging(Self.robot(Self.near, rssi: -40), into: list)

        #expect(list.map(\.rssi) == [-40, -88])
    }

    /// Robots advertise one shared name, so ties are common and an order that depends on
    /// arrival would reshuffle the list under the user's finger on every sighting.
    @Test("two indistinguishable robots keep the same order whichever arrives first")
    func ordersTiesDeterministically() {
        let first = CoreBluetoothTransport.merging(
            Self.robot(Self.far, rssi: -60),
            into: [Self.robot(Self.near, rssi: -60)]
        )
        let second = CoreBluetoothTransport.merging(
            Self.robot(Self.near, rssi: -60),
            into: [Self.robot(Self.far, rssi: -60)]
        )

        #expect(first.map(\.id) == second.map(\.id))
    }
}
