import Foundation

/// The rest of `/wifi/*`, beyond what provisioning needs.
///
/// Kept apart from `WiFiProvisioningTransport` because forgetting a saved network is
/// settings work on a robot already on the LAN — and offering it during setup, over the
/// very hotspot the phone is standing on, is a way to strand both ends.
public protocol WiFiConfigClient: WiFiProvisioningTransport {
    func forget(ssid: String) async throws
    func forgetAll() async throws
    /// Why the last join failed. The connect route answers immediately and does the work
    /// on a background thread, so this is where the reason ends up.
    func lastWiFiError() async throws -> String?
    func resetWiFiError() async throws
}
