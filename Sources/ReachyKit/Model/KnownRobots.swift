import Foundation

/// Persistence for the last successfully connected robot address.
/// Manual reconnection to a known address is a first-class flow (issue #269).
public enum KnownRobots {
    private static let lastAddressKey = "ReachyKit.lastAddress"

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
}
