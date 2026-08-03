import Foundation

public enum ReachyKitError: Error, Sendable, Equatable {
    /// The robot address could not be turned into a valid URL (e.g. malformed host).
    case invalidAddress(RobotAddress)
    /// An operation requiring an active daemon connection was requested while disconnected.
    case notConnected
    /// The daemon API is older than the minimum or belongs to another major version.
    case unsupportedDaemonVersion(reported: String, minimum: String)
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
        }
    }
}
