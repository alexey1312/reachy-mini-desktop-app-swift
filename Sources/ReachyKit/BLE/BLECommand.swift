import Foundation

/// A command written to the command characteristic as a UTF-8 string.
///
/// The robot dispatches on the *uppercased* string, except `PIN_` and `CMD_` which it
/// matches case-sensitively, and it slices arguments out of the **original-case**
/// string. So SSIDs, robot names and JSON survive verbatim even though the verb does
/// not have to be typed exactly.
///
/// This is the whole set the robot answers. Renaming is deliberately absent: the dispatch
/// in `bluetooth_service.py` has no `SET_NAME` branch and falls through to `ECHO:`, so a
/// rename only works over HTTP, once the robot is on a network.
public enum BLECommand: Equatable, Sendable {
    case ping
    case status
    case authenticate(pin: String)
    case wifiStatus
    case wifiScan
    case wifiKeyExchange
    case wifiConnectSealed(json: String)
    case wifiForget(ssid: String)
    case updateCheck
    case updateStart
    case updateInfo(jobID: String)
    case journalStart
    case journalRead
    case journalStop
    /// Runs `commands/<script>.sh` on the robot. Fire-and-forget: see `repliesToWrite`.
    case runScript(String)

    public var wireFormat: String {
        switch self {
        case .ping: "PING"
        case .status: "STATUS"
        case let .authenticate(pin): "PIN_\(pin)"
        case .wifiStatus: "WIFI_STATUS"
        case .wifiScan: "WIFI_SCAN"
        case .wifiKeyExchange: "WIFI_KEYEX"
        case let .wifiConnectSealed(json): "WIFI_CONNECT_ENC \(json)"
        case let .wifiForget(ssid): "WIFI_FORGET \(ssid)"
        case .updateCheck: "UPDATE_CHECK"
        case .updateStart: "UPDATE_START"
        case let .updateInfo(jobID): "UPDATE_INFO \(jobID)"
        case .journalStart: "JOURNAL_START"
        case .journalRead: "JOURNAL_READ"
        case .journalStop: "JOURNAL_STOP"
        case let .runScript(script): "CMD_\(script)"
        }
    }

    /// `CMD_*` returns `None` from the robot's handler on success, so the service
    /// crashes encoding the reply and the GATT write reports an error even though the
    /// script ran. Nothing can be awaited; verify by side effect instead.
    public var repliesToWrite: Bool {
        if case .runScript = self {
            return false
        }
        return true
    }

    /// Whether a live PIN session is required. `WIFI_KEYEX` is public because a bare
    /// public key is useless without the PIN, and `WIFI_STATUS` merely withholds the
    /// saved-network list from unauthenticated peers.
    public var needsSession: Bool {
        switch self {
        case .wifiScan, .wifiConnectSealed, .wifiForget,
             .updateCheck, .updateStart, .updateInfo, .runScript:
            true
        case .ping, .status, .authenticate, .wifiStatus, .wifiKeyExchange,
             .journalStart, .journalRead, .journalStop:
            false
        }
    }

    /// Commands the robot proxies to the daemon run off the BLE mainloop and answer
    /// twice — an immediate ack, then the real result as a notification. `nmcli`
    /// rescan alone can take 15 s, so these need a far longer budget than a `PING`.
    public var timeout: Duration {
        switch self {
        case .wifiScan: .seconds(30)
        case .updateCheck, .updateStart, .updateInfo: .seconds(40)
        case .wifiConnectSealed, .wifiForget, .wifiStatus, .wifiKeyExchange: .seconds(20)
        default: .seconds(5)
        }
    }

    public var data: Data {
        Data(wireFormat.utf8)
    }
}
