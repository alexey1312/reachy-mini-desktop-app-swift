import CoreBluetooth
@testable import ReachyKit
import Testing

/// The live half needs a radio and a prompt, so what is checked here is the mapping —
/// the same shape as `CoreBluetoothTransportTests.mapsManagerStates`, and for the same
/// reason: it is the part carrying a decision.
@Suite("BluetoothPermission")
struct BluetoothPermissionTests {
    @Test("every authorization maps to something the screen can act on")
    func mapsAuthorizations() {
        #expect(BluetoothPermission.state(for: .allowedAlways) == .granted)
        #expect(BluetoothPermission.state(for: .denied) == .denied)
        #expect(BluetoothPermission.state(for: .notDetermined) == .undetermined)
        // Not folded into `.denied`: the Settings toggle exists and this user cannot
        // move it, so the screen must not send them to go and try.
        #expect(BluetoothPermission.state(for: .restricted) == .restricted)
    }

    @Test("only an allowed authorization is non-blocking")
    func blocking() {
        let blocking = PermissionState.allCases.filter(\.isBlocking)
        #expect(blocking == [.denied, .restricted])
    }
}
