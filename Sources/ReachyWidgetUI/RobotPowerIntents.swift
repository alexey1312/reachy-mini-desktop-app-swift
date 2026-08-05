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
    /// One connection whose every sub-session is capped at `timeout`.
    ///
    /// `RobotConnection` reuses an injected session for all of them, including the
    /// 35-second hub session that `/api/apps/*` normally runs on — which is the
    /// point here rather than a side effect. That budget exists for a screen with
    /// a spinner; an intent that sat on it would be killed with nothing written
    /// down.
    public static func connection(timeout: TimeInterval) throws -> RobotConnection {
        guard let address = KnownRobots.lastAddress else {
            throw RobotIntentError.noKnownRobot
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        do {
            return try RobotConnection(address: address, session: URLSession(configuration: configuration))
        } catch {
            throw RobotIntentError.unreachable(RobotSession.describe(error))
        }
    }

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
    // Runs in the background, which is the default and the only thing that works
    // here. `openAppWhenRun = true` would bring the app forward, but it is
    // deprecated *and* errors when the intent runs in an app extension — exactly
    // where a Control Centre button runs it. Its replacement, `supportedModes`,
    // is iOS 26 and this app deploys to 18.
    //
    // Background means the extension's own process, which cannot ask for Local
    // Network access: it has no screen to prompt from, and a denial there is
    // silent. Safe only because the intent already requires a robot this app has
    // connected to before, and that connection is what obtained the permission.

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

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await RobotIntentTarget.power().sleep()
        return .result()
    }
}
