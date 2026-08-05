import Foundation

/// Somewhere in the app a widget can send the user.
///
/// The scheme is the one the OAuth callback already uses, because an app gets one
/// and registering a second buys nothing. Parsing is therefore exact rather than
/// forgiving: `oauth-callback` belongs to `ASWebAuthenticationSession`, and
/// anything else in this scheme is not ours to interpret.
public enum ReachyDeepLink: String, CaseIterable, Sendable {
    case robot
    case apps

    public static let scheme = "reachy-mini-swift"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = rawValue
        // The components above are fixed and valid; a nil here would be a bug in
        // this type rather than anything a caller can cause.
        guard let url = components.url else {
            preconditionFailure("deep link components do not form a URL: \(rawValue)")
        }
        return url
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        self.init(rawValue: host)
    }
}
