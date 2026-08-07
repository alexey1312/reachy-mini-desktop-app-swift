import Foundation

/// The semantic state published by Conversation App 1.0's JSON-RPC surface.
///
/// Kept separate from ``RobotAppStatus/State``: the daemon reports whether the
/// process is running, while the app reports what one conversation turn is doing.
public enum ConversationTurn: Sendable, Equatable, Decodable {
    case listening
    case thinking
    case speaking
    case ready
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "listening": self = .listening
        case "thinking": self = .thinking
        case "speaking": self = .speaking
        case "ready": self = .ready
        case let other: self = .unknown(other)
        }
    }
}
