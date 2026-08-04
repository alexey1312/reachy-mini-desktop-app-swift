import Foundation

/// Why a connection stopped at the compatibility gate, and whether the app can do
/// anything about it.
public struct DaemonUpdateRequirement: Equatable, Sendable {
    public let reported: String
    public let minimum: String
    /// `/update/*` is mounted only under `--wireless-version`. A Lite robot cannot be
    /// updated over the network at all — it needs the desktop app over USB — so the
    /// screen has to offer an explanation rather than a button.
    public let canSelfUpdate: Bool

    public init(reported: String, minimum: String, canSelfUpdate: Bool) {
        self.reported = reported
        self.minimum = minimum
        self.canSelfUpdate = canSelfUpdate
    }
}

/// What `GET /update/available` says about the robot's own software.
public enum DaemonUpdateAvailability: Sendable, Equatable {
    case upToDate(current: String)
    case available(current: String, latest: String)
    /// The daemon answered but could not reach PyPI, reporting the literal string
    /// `"unknown"` as the available version. The robot's connectivity is at fault,
    /// not the request — telling the user the check failed would send them looking
    /// in the wrong place.
    case robotOffline(current: String)

    public var currentVersion: String {
        switch self {
        case let .upToDate(current), let .available(current, _), let .robotOffline(current):
            current
        }
    }

    /// Decodes the daemon's doubly-nested payload:
    /// `{"update": {"reachy_mini": {"is_available", "current_version", "available_version"}}}`.
    struct Response: Decodable {
        struct Package: Decodable {
            let isAvailable: Bool
            let currentVersion: String
            let availableVersion: String

            enum CodingKeys: String, CodingKey {
                case isAvailable = "is_available"
                case currentVersion = "current_version"
                case availableVersion = "available_version"
            }
        }

        let update: [String: Package]

        /// The daemon keys the map by distribution name; `reachy_mini` is the only
        /// one it ever reports, but reading the sole value survives a rename.
        var availability: DaemonUpdateAvailability? {
            guard let package = update["reachy_mini"] ?? update.values.first else { return nil }
            if package.availableVersion == "unknown" {
                return .robotOffline(current: package.currentVersion)
            }
            return package.isAvailable
                ? .available(current: package.currentVersion, latest: package.availableVersion)
                : .upToDate(current: package.currentVersion)
        }
    }
}

/// A background job on the daemon — here, always `update_reachy_mini`.
public struct DaemonUpdateJob: Sendable, Equatable, Decodable {
    /// An unrecognised value decodes to `.unknown` rather than throwing: the daemon
    /// versions independently of this app, and a job whose status stopped parsing
    /// must not read as a failed update. The socket closing is the real end signal.
    public enum Status: Sendable, Equatable, Decodable {
        case pending
        case inProgress
        case done
        case failed
        case unknown(String)

        public init(from decoder: any Decoder) throws {
            switch try decoder.singleValueContainer().decode(String.self) {
            case "pending": self = .pending
            case "in_progress": self = .inProgress
            case "done": self = .done
            case "failed": self = .failed
            case let other: self = .unknown(other)
            }
        }

        public var isTerminal: Bool {
            self == .done || self == .failed
        }
    }

    public let command: String
    public let status: Status
    public let logs: [String]

    public init(command: String, status: Status, logs: [String]) {
        self.command = command
        self.status = status
        self.logs = logs
    }
}
