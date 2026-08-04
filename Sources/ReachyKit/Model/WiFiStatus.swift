import Foundation

/// The robot's Wi-Fi state, as reported by both `WIFI_STATUS` over BLE and
/// `GET /wifi/status` over HTTP.
public struct WiFiStatus: Equatable, Sendable, Decodable {
    public enum Mode: String, Equatable, Sendable {
        case hotspot
        case wlan
        case disconnected
        /// An `nmcli` operation is in flight. Transient — keep polling.
        case busy
    }

    /// Nil when the BLE service could not reach the daemon at all.
    public let mode: Mode?
    /// The SSID the robot has actually joined.
    public let connected: String?
    /// Saved networks. Withheld from unauthenticated peers, because the list of
    /// networks a robot knows is a fingerprint of where its owner lives.
    public let known: [String]?
    public let error: String?

    public init(mode: Mode?, connected: String?, known: [String]? = nil, error: String? = nil) {
        self.mode = mode
        self.connected = connected
        self.known = known
        self.error = error
    }

    public func hasJoined(_ ssid: String) -> Bool {
        mode == .wlan && connected == ssid && error == nil
    }

    /// A failed join drops the robot back onto its own access point, so this is what
    /// "the password was wrong" looks like from the client side.
    public var didFallBackToHotspot: Bool {
        mode == .hotspot
    }

    private enum CodingKeys: String, CodingKey {
        case mode, connected, known, error
        // `GET /wifi/status` spells the same two fields differently from the BLE relay.
        case knownNetworks = "known_networks"
        case connectedNetwork = "connected_network"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An unrecognised mode decodes to nil rather than throwing: the daemon versions
        // independently, and a new state must not break a status poll mid-provisioning.
        mode = try container.decodeIfPresent(String.self, forKey: .mode).flatMap(Mode.init(rawValue:))
        connected = try container.decodeIfPresent(String.self, forKey: .connected)
            ?? container.decodeIfPresent(String.self, forKey: .connectedNetwork)
        known = try container.decodeIfPresent([String].self, forKey: .known)
            ?? container.decodeIfPresent([String].self, forKey: .knownNetworks)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}
