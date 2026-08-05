import Foundation

/// What the app last saw of a robot, for a process that cannot look for itself.
///
/// A widget extension is woken for a moment, renders, and is gone. It can hold
/// neither the state WebSocket nor a WebRTC session, so it shows what the app
/// wrote the last time it was connected — and `takenAt` is what keeps that
/// honest rather than merely confident.
public struct RobotSnapshot: Codable, Sendable, Equatable {
    /// Stable identity of the robot that produced this reading. Optional only so
    /// snapshots written before identity was persisted still decode.
    public let robotID: String?
    /// Nil for a robot whose daemon never answered a name — the same daemons
    /// that cannot be renamed at all.
    public let robotName: String?
    public let isAwake: Bool
    /// The app the robot is running, when it is running one — its display title,
    /// which is what a widget puts on screen.
    public let runningApp: String?
    /// The same app's installed name, which is the identity `start-app` and
    /// `stop-current-app` are keyed by. A title cannot stand in for it: the two
    /// are chosen independently (`RobotApp.matches(installed:)`).
    ///
    /// Defaulted so a blob written before this field existed decodes as a robot
    /// running nothing identifiable rather than failing.
    public let runningAppName: String?
    /// When the running app itself was checked. Status polling refreshes
    /// `takenAt`, but cannot refresh this without another robot round trip.
    public let runningAppTakenAt: Date?
    /// When the app saw this. Not decoration: everything below turns on it.
    public let takenAt: Date

    public init(
        robotID: String? = nil,
        robotName: String?,
        isAwake: Bool,
        runningApp: String?,
        runningAppName: String? = nil,
        runningAppTakenAt: Date? = nil,
        takenAt: Date
    ) {
        self.robotID = robotID
        self.robotName = robotName
        self.isAwake = isAwake
        self.runningApp = runningApp
        self.runningAppName = runningAppName
        self.runningAppTakenAt = runningAppTakenAt
        self.takenAt = takenAt
    }

    /// The app observation expires independently of the daemon status. For a
    /// legacy snapshot without its own date, the snapshot date is the safest
    /// compatible approximation.
    public func runningAppName(at date: Date) -> String? {
        guard runningAppIsFresh(at: date) else { return nil }
        return runningAppName
    }

    public func runningAppTitle(at date: Date) -> String? {
        guard runningAppIsFresh(at: date) else { return nil }
        return runningApp ?? runningAppName
    }

    public var runningAppExpiresAt: Date? {
        guard runningApp != nil || runningAppName != nil else { return nil }
        return (runningAppTakenAt ?? takenAt).addingTimeInterval(RobotSnapshotStore.freshness)
    }

    private func runningAppIsFresh(at date: Date) -> Bool {
        guard let expiry = runningAppExpiresAt else { return false }
        return date <= expiry
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

    /// Folds what a caller just learned about the running app into the reading
    /// already there, inventing nothing else about it.
    ///
    /// `takenAt` moves to `date` because whoever calls this has just spoken to the
    /// robot — the reading genuinely is that fresh, even though only one field of
    /// it was re-checked. Both name parameters nil is "nothing is running", not "I
    /// do not know", so it clears rather than leaves the last app behind.
    ///
    /// `isAwake` is for a caller that learned it in the same breath; nil keeps
    /// what was already there. The `true` floor is only reached when no reading
    /// exists at all, and every caller here has just commanded a robot
    /// successfully — which a parked one does not answer.
    public func recordRunningApp(
        title: String?,
        name: String?,
        robotID: String? = nil,
        robotName: String? = nil,
        isAwake: Bool? = nil,
        at date: Date = Date()
    ) {
        let previous = current
        let resolvedID = robotID ?? previous?.robotID
        let sameRobot = robotID == nil || previous?.robotID == robotID
        let hasRunningApp = title != nil || name != nil
        write(RobotSnapshot(
            robotID: resolvedID,
            robotName: robotName ?? (sameRobot ? previous?.robotName : nil),
            isAwake: isAwake ?? (sameRobot ? previous?.isAwake : nil) ?? true,
            runningApp: title,
            runningAppName: name,
            runningAppTakenAt: hasRunningApp ? date : nil,
            takenAt: date
        ))
    }
}
