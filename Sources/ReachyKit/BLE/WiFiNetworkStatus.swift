import Foundation

/// The network-status characteristic, which is plain text rather than JSON:
/// `"{MODE} [iface] ip ; [iface] ip"`, or a bare `"OFFLINE"` when the robot has no
/// interfaces at all.
///
/// This is the live address, unlike the Device Information "firmware revision"
/// characteristic, which the robot abuses to carry `"[HOTSPOT]:<ip>"` and never
/// refreshes after boot.
public struct WiFiNetworkStatus: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case hotspot = "HOTSPOT"
        case connected = "CONNECTED"
        case offline = "OFFLINE"
        case error = "ERROR"
    }

    public struct Interface: Equatable, Sendable {
        public let name: String
        public let address: String
    }

    public let mode: Mode
    public let interfaces: [Interface]

    /// The address to reach the daemon on. In hotspot mode this is the well-known
    /// `10.42.0.1`; on a joined network it is whatever DHCP handed out.
    public var address: String? {
        interfaces.first { $0.name == "wlan0" }?.address ?? interfaces.first?.address
    }

    public init?(parsing raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let head = text.prefix { $0 != "[" }.trimmingCharacters(in: .whitespaces)
        guard let mode = Mode(rawValue: head) else { return nil }
        self.mode = mode

        interfaces = text
            .dropFirst(head.count)
            .split(separator: ";")
            .compactMap(Self.interface(in:))
    }

    /// The same reading in the vocabulary both channels share. The address does not
    /// survive the trip — `WiFiStatus` has nowhere to put it, because `GET /wifi/status`
    /// has no address in it — so read this type directly when the address is the point.
    public var status: WiFiStatus {
        let shared: WiFiStatus.Mode? = switch mode {
        case .hotspot: .hotspot
        case .connected: .wlan
        case .offline: .disconnected
        // The characteristic says only that the robot failed, never which network it
        // was reaching for, so there is no SSID to report alongside it.
        case .error: nil
        }
        return WiFiStatus(
            mode: shared,
            connected: nil,
            error: mode == .error ? "The robot reported a Wi-Fi error." : nil
        )
    }

    /// One `"[wlan0] 192.168.1.42"` segment.
    private static func interface(in segment: some StringProtocol) -> Interface? {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") else { return nil }
        let name = String(trimmed[trimmed.index(after: trimmed.startIndex) ..< close])
        let address = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !address.isEmpty else { return nil }
        return Interface(name: name, address: address)
    }
}
