import Foundation

/// What the app last saw of a robot, for a process that cannot look for itself.
///
/// A widget extension is woken for a moment, renders, and is gone. It can hold
/// neither the state WebSocket nor a WebRTC session, so it shows what the app
/// wrote the last time it was connected — and `takenAt` is what keeps that
/// honest rather than merely confident.
public struct RobotSnapshot: Codable, Sendable, Equatable {
    /// Nil for a robot whose daemon never answered a name — the same daemons
    /// that cannot be renamed at all.
    public let robotName: String?
    public let isAwake: Bool
    /// The app the robot is running, when it is running one.
    public let runningApp: String?
    /// When the app saw this. Not decoration: everything below turns on it.
    public let takenAt: Date

    public init(robotName: String?, isAwake: Bool, runningApp: String?, takenAt: Date) {
        self.robotName = robotName
        self.isAwake = isAwake
        self.runningApp = runningApp
        self.takenAt = takenAt
    }
}

/// Whether a snapshot is still worth stating as fact.
public enum RobotSnapshotState: Sendable, Equatable {
    /// No robot has been connected, or the last one was let go of. Nothing to
    /// show, and nothing to guess.
    case unknown
    /// Recent enough to describe in the present tense.
    case fresh(RobotSnapshot)
    /// Old enough that the robot may have been switched off since — a robot
    /// leaving does not announce itself. Say when it was seen, not what it is
    /// doing.
    case stale(RobotSnapshot)
}

/// The snapshot, in storage both processes can reach.
public struct RobotSnapshotStore {
    static let key = "ReachyKit.robotSnapshot"

    /// How long a reading is repeated as current.
    ///
    /// A robot switched off, unplugged or carried out of range tells nobody, and
    /// the app is not running to notice. Half an hour is long enough to cover a
    /// phone put down mid-session and short enough that a widget does not
    /// describe yesterday's robot in the present tense.
    public static let freshness: TimeInterval = 30 * 60

    private let defaults: UserDefaults

    /// Defaults to the shared group, which is the only store the widget can read.
    public init(defaults: UserDefaults = KnownRobots.defaults) {
        self.defaults = defaults
    }

    public var current: RobotSnapshot? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(RobotSnapshot.self, from: data)
    }

    public func write(_ snapshot: RobotSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Called when the session ends: a reading left behind would have the widget
    /// describe a robot the user deliberately disconnected from.
    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    public func state(at date: Date = Date()) -> RobotSnapshotState {
        guard let current else { return .unknown }
        // A negative age is a clock that moved backwards — a timezone change, a
        // manual correction — not a reading from the future gone stale.
        let age = date.timeIntervalSince(current.takenAt)
        return age <= Self.freshness ? .fresh(current) : .stale(current)
    }
}
