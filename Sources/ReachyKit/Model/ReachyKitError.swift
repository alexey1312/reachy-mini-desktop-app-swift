import Foundation

public enum ReachyKitError: Error, Sendable, Equatable {
    /// The robot address could not be turned into a valid URL (e.g. malformed host).
    case invalidAddress(RobotAddress)
    /// An operation requiring an active daemon connection was requested while disconnected.
    case notConnected
}
