import Foundation

public enum ReachyKitError: Error, Sendable, Equatable {
    /// The robot address could not be turned into a valid URL (e.g. malformed host).
    case invalidAddress(RobotAddress)
    /// An operation requiring an active daemon connection was requested while disconnected.
    case notConnected
    /// The daemon API is older than the minimum or belongs to another major version.
    case unsupportedDaemonVersion(reported: String, minimum: String)
    /// HTTP 503: the daemon answers, but the robot backend is torn down — every
    /// motion route is guarded by it.
    case backendNotRunning
    /// HTTP 409: a start/stop/restart job is already in flight daemon-side.
    case daemonBusy
    /// Any other status the daemon rejected the call with.
    case daemonRejected(statusCode: Int)

    /// Maps a daemon HTTP status onto the cases callers can act on.
    static func fromStatusCode(_ statusCode: Int) -> ReachyKitError {
        switch statusCode {
        case 503: .backendNotRunning
        case 409: .daemonBusy
        default: .daemonRejected(statusCode: statusCode)
        }
    }
}

extension ReachyKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidAddress(address):
            "Invalid robot address: \(address.host):\(address.port)"
        case .notConnected:
            "Not connected to a robot"
        case let .unsupportedDaemonVersion(reported, minimum):
            "Unsupported daemon \(reported); this app requires daemon \(minimum)"
        case .backendNotRunning:
            "The robot backend is not running — start it before moving the robot"
        case .daemonBusy:
            "The daemon is busy with another operation; try again in a moment"
        case let .daemonRejected(statusCode):
            "The daemon rejected the request (HTTP \(statusCode))"
        }
    }
}
