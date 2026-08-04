import Foundation

/// Persistence for the robots this app has connected to.
/// Manual reconnection to a known address is a first-class flow (issue #269).
public enum KnownRobots {
    private static let onboardingKey = "ReachyKit.hasCompletedOnboarding"
    private static let provisionedKey = "ReachyKit.pendingProvisionedHardwareID"

    public static var store: KnownRobotStore {
        KnownRobotStore(defaults: .standard)
    }

    /// Robots seen through a completed handshake, most recent first.
    public static var all: [KnownRobot] {
        store.all
    }

    /// The address to offer first: what the manual field shows and what the candidate
    /// sweep tries before anything else. Identity-keyed records live in `all`.
    public static var lastAddress: RobotAddress? {
        get { store.lastAddress }
        set { store.lastAddress = newValue }
    }

    public static func remember(identity: RobotIdentity, address: RobotAddress, at date: Date = Date()) {
        store.remember(identity: identity, address: address, at: date)
    }

    public static func forget(_ key: String) {
        store.forget(key)
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
