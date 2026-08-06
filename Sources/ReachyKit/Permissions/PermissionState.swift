import Foundation

/// Whether the user has granted one of the three device permissions this app asks
/// for — Bluetooth, Local Network, the microphone.
///
/// Four cases, not five: there is deliberately no `unavailable`. Absent hardware is
/// not a permission answer, and treating it as one would be wrong in both
/// directions — a Simulator has no Bluetooth radio at all and still reports its
/// authorization as `.notDetermined`. That axis already has a home in
/// `BLEAvailability`, which is read off a live central's `CBManagerState`.
public enum PermissionState: Sendable, Equatable, CaseIterable {
    /// Never asked, or asked and not answered yet.
    case undetermined
    case granted
    /// The user said no. Only a trip to Settings undoes it.
    case denied
    /// Withheld by policy — Screen Time, MDM, a supervised device. Not `denied`
    /// with different wording: the Settings toggle exists and the user cannot move
    /// it, so sending them to flip a switch they do not own is worse than saying so.
    case restricted
}

public extension PermissionState {
    /// The two states that stop a feature working. Callers need the pair constantly,
    /// and spelling it out at each site is how one of them ends up forgotten.
    var isBlocking: Bool {
        self == .denied || self == .restricted
    }
}
