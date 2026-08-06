import CoreBluetooth

/// Whether this app may use Bluetooth — answered without touching the radio.
///
/// `CBCentralManager.authorization` is a *class* property. Reading it builds no
/// central and raises no prompt, which is the whole reason this type exists:
/// `CoreBluetoothTransport` prompts by being initialised (see its own doc comment),
/// so a screen that merely lists what the app needs cannot ask it.
///
/// It answers authorization and nothing else. `CBManagerAuthorization` has no
/// "switched off" and no "this device has no radio" — a Simulator, which has
/// neither, still reports `.notDetermined`. `BLEAvailability` is where that lives,
/// and getting it costs a live central, which costs the prompt.
public enum BluetoothPermission {
    /// Non-prompting. Safe to read on `onAppear`.
    public static var current: PermissionState {
        state(for: CBCentralManager.authorization)
    }

    /// Raises the system prompt and waits for the radio to say something definite.
    ///
    /// **Building a central is the prompt** — there is no `requestAuthorization` for
    /// Bluetooth — so this is only ever called from an explicit action on a screen that
    /// has already explained why. `CoreBluetoothTransport`'s own doc comment is the rule
    /// this observes.
    ///
    /// It returns the *availability*, not the authorization, because that is the half
    /// only a live central can answer: read `current` afterwards for the other. Waiting
    /// for a state that is not `.unknown` is what makes this land after the user has
    /// answered rather than before — `events()` replays the current value on subscribe,
    /// so a permission already settled resolves immediately and never waits out the
    /// timeout.
    public static func promptForAccess(timeout: Duration = .seconds(30)) async -> BLEAvailability {
        let transport = CoreBluetoothTransport()
        return await withTaskGroup(of: BLEAvailability?.self) { group in
            group.addTask {
                for await event in transport.events() {
                    guard case let .availabilityChanged(availability) = event, availability != .unknown else {
                        continue
                    }
                    return availability
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            // A prompt left unanswered until the timeout still has a snapshot behind it,
            // and it is `.unknown` — which is the honest answer, not a failure.
            return first ?? transport.availability
        }
    }

    static func state(for authorization: CBManagerAuthorization) -> PermissionState {
        switch authorization {
        case .allowedAlways: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .undetermined
        @unknown default: .undetermined
        }
    }
}
