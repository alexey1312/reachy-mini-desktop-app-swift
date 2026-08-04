import Foundation

/// Persistence for the last successfully connected robot address.
/// Manual reconnection to a known address is a first-class flow (issue #269).
public enum KnownRobots {
    private static let lastAddressKey = "ReachyKit.lastAddress"
    private static let onboardingKey = "ReachyKit.hasCompletedOnboarding"
    private static let provisionedKey = "ReachyKit.pendingProvisionedHardwareID"

    public static var lastAddress: RobotAddress? {
        get {
            guard let data = UserDefaults.standard.data(forKey: lastAddressKey) else { return nil }
            return try? JSONDecoder().decode(RobotAddress.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: lastAddressKey)
                return
            }
            UserDefaults.standard.set(data, forKey: lastAddressKey)
        }
    }

    /// Whether the first-run flow has already run. It only stops onboarding from opening
    /// itself a second time — the flow is never a gate, and stays reachable by hand.
    public static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingKey) }
    }

    /// A robot just given a Wi-Fi password over Bluetooth, waiting to be recognised once
    /// it appears on the network.
    ///
    /// The hardware id rather than the address, because the address is exactly what
    /// changes: the robot is provisioned on its own hotspot and comes back on the home
    /// network at whatever DHCP hands out (rule 4).
    public static var pendingProvisionedHardwareID: String? {
        get { UserDefaults.standard.string(forKey: provisionedKey) }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: provisionedKey)
                return
            }
            UserDefaults.standard.set(newValue, forKey: provisionedKey)
        }
    }
}
