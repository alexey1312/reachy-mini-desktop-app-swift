import Foundation

/// A background job on the daemon — an app install, removal or update, or the
/// daemon's own software update.
///
/// One type for both because there is literally one implementation behind them:
/// `/api/apps/*` and `/update/*` hand their work to the same
/// `bg_job_register.run_command`, and both report it through the same `JobInfo`.
public struct DaemonJob: Sendable, Equatable, Decodable {
    /// An unrecognised value decodes to `.unknown` rather than throwing: the daemon
    /// versions independently of this app, and a job whose status stopped parsing
    /// must not read as a failed install. The socket closing is the real end signal.
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

/// The name the update screens have always used.
public typealias DaemonUpdateJob = DaemonJob
