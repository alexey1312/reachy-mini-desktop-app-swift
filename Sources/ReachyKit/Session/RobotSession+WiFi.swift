import Foundation

/// The robot's own network settings, reached through the session so the UI never builds a
/// URL of its own.
///
/// Provisioning is not here. Handing over a password is `WiFiProvisioningTransport`, which
/// works over Bluetooth too; these are the routes that only make sense once the robot is
/// already reachable.
public extension RobotSession {
    /// False on a Lite robot, which never mounts `/wifi/*`.
    var canConfigureWiFi: Bool {
        client is any WiFiConfigClient && supportsWirelessFeatures
    }

    func wifiStatus() async throws -> WiFiStatus {
        try await withWiFiClient { try await $0.wifiStatus() }
    }

    /// Answers 404 for a network the robot never saved, and refuses its own hotspot.
    func forgetWiFi(ssid: String) async throws {
        try await withWiFiClient { try await $0.forget(ssid: ssid) }
    }

    /// Why the last join failed. `connect_sealed` returns before it joins, so this is
    /// where the reason ends up rather than in the reply.
    func lastWiFiError() async throws -> String? {
        try await withWiFiClient { try await $0.lastWiFiError() }
    }

    func resetWiFiError() async throws {
        try await withWiFiClient { try await $0.resetWiFiError() }
    }
}

extension RobotSession {
    func withWiFiClient<T>(_ call: (any WiFiConfigClient) async throws -> T) async throws -> T {
        guard let client else { throw ReachyKitError.notConnected }
        guard let wifiClient = client as? any WiFiConfigClient else {
            throw ReachyKitError.wirelessFeaturesUnavailable
        }
        return try await call(wifiClient)
    }
}
