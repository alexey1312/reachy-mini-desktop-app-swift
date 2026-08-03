import Foundation

enum LogLevel: Int, CaseIterable, Sendable, Comparable, CustomStringConvertible {
    case debug, info, warning, error

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .warning: "warning"
        case .error: "error"
        }
    }
}

/// One journal line. `text` stays identical to what the daemon sent — copy and
/// export ship the original, not a re-rendered version.
struct LogEntry: Identifiable, Sendable, Equatable {
    let id: Int
    let timestamp: String?
    let message: String
    let level: LogLevel
    let text: String

    init(id: Int, raw: String) {
        self.id = id
        text = raw
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, let first = parts.first, Self.isTimestamp(first) {
            timestamp = String(first)
            message = String(parts[1])
        } else {
            timestamp = nil
            message = raw
        }
        level = Self.level(of: message)
    }

    private static func isTimestamp(_ token: Substring) -> Bool {
        token.count >= 19 && token.dropFirst(10).first == "T" && token.prefix(4).allSatisfy(\.isNumber)
    }

    /// journalctl `short-iso` carries no priority field and the daemon is a Python
    /// service, so the level exists only as a token inside the message. Matching is
    /// case-sensitive so prose like "error rate" is not flagged.
    private static func level(of message: String) -> LogLevel {
        if message.contains("ERROR") || message.contains("CRITICAL") || message.contains("FATAL")
            || message.contains("Traceback")
        {
            return .error
        }
        if message.contains("WARN") {
            return .warning
        }
        if message.contains("DEBUG") {
            return .debug
        }
        return .info
    }
}
