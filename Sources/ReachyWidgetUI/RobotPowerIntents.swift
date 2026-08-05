import AppIntents
import ReachyKit

/// Why an intent can fail before it ever reaches a robot.
///
/// Shortcuts shows this text and nothing else, so each case has to say what the
/// user can do about it rather than what went wrong internally.
public enum RobotIntentError: Error, LocalizedError {
    case noKnownRobot
    case unreachable(String)

    public var errorDescription: String? {
        switch self {
        case .noKnownRobot:
            "No robot to reach. Open Reachy Mini and connect to one first."
        case let .unreachable(reason):
            reason
        }
    }
}

/// The robot an intent acts on: the last one this app connected to, at the
/// address it answered on.
///
/// **Local network only, deliberately.** A robot reached through the Hugging Face
/// relay needs a WebRTC session negotiated over a signalling stream, and an intent
/// does not have the time budget for that — it would sit there and then fail. Away
/// from the robot's network this fails immediately and says so, which is the
/// honest outcome rather than a slow one.
public enum RobotIntentTarget {
    public static func power() throws -> RobotPower {
        guard let address = KnownRobots.lastAddress else {
            throw RobotIntentError.noKnownRobot
        }
        do {
            return try RobotPower(client: RobotConnection(address: address))
        } catch {
            throw RobotIntentError.unreachable(RobotSession.describe(error))
        }
    }
}

public struct WakeRobotIntent: AppIntent {
    public static let title: LocalizedStringResource = "Wake Reachy Mini"
    public static let description = IntentDescription(
        "Enables the robot's motors and plays its wake-up animation."
    )
    /// Motion, so the app comes forward rather than moving a robot the user may
    /// not be looking at from a locked phone.
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await RobotIntentTarget.power().wake()
        return .result()
    }
}

public struct SleepRobotIntent: AppIntent {
    public static let title: LocalizedStringResource = "Put Reachy Mini to sleep"
    public static let description = IntentDescription(
        "Plays the robot's sleep animation, then parks its motors."
    )
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await RobotIntentTarget.power().sleep()
        return .result()
    }
}
