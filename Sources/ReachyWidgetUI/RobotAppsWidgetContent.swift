import Foundation
import ReachyKit

/// What the launcher puts on screen, worked out from storage before any view is
/// involved — the same split as `RobotWidgetContent`, and for the same reason:
/// every rule below is decided here, where it can be tested without rendering.
///
/// The rule that matters most is inherited too. A reading past its window is
/// never restated as fact, so a stale snapshot claims **no** app is running
/// rather than the one it happened to see. A widget insisting an app is running
/// an hour after the robot was switched off is worse than one admitting it does
/// not know.
public struct RobotAppsWidgetContent: Equatable, Sendable {
    public enum TileState: Equatable, Sendable {
        case idle
        case running
        case starting
        case stopping
        /// Another app holds the robot. Tappable would mean evicting it, which the
        /// Apps screen refuses too.
        case blocked
        /// Configured once, gone from the robot since — or never resolvable. Kept
        /// visible so a configuration is not silently rewritten behind the user.
        case notInstalled
    }

    public struct Tile: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let title: String
        public let emoji: String?
        public let gradient: RobotApp.Gradient?
        public let state: TileState

        public init(
            id: String,
            name: String,
            title: String,
            emoji: String? = nil,
            gradient: RobotApp.Gradient? = nil,
            state: TileState
        ) {
            self.id = id
            self.name = name
            self.title = title
            self.emoji = emoji
            self.gradient = gradient
            self.state = state
        }

        public var isTappable: Bool {
            switch state {
            case .idle, .running: true
            case .starting, .stopping, .blocked, .notInstalled: false
            }
        }
    }

    /// The one line under the tiles. At most one thing is worth saying.
    public enum Notice: Equatable, Sendable {
        case none
        case noRobot
        case noApps
        /// The robot is busy with something the user did not put on this widget,
        /// so nothing on screen explains why everything is dimmed.
        case busy(String)
        case failure(String)

        public var message: String? {
            switch self {
            case .none: nil
            case .noRobot: "No robot. Open Reachy Mini to connect."
            case .noApps: "No apps yet. Open Reachy Mini to load your robot's apps."
            case let .busy(title): "“\(title)” is running."
            case let .failure(reason): reason
            }
        }

        /// Whether tapping the notice is worth suggesting. Everything here is
        /// resolved in the app, so this is only about how loudly to say so.
        public var invitesTheApp: Bool {
            switch self {
            case .none, .busy: false
            case .noRobot, .noApps, .failure: true
            }
        }
    }

    public let tiles: [Tile]
    public let notice: Notice
    /// Set only once the list is past `RobotAppsCache.freshness`. A menu going old
    /// is worth admitting, not worth refusing to serve.
    public let footnote: String?

    public init(tiles: [Tile], notice: Notice = .none, footnote: String? = nil) {
        self.tiles = tiles
        self.notice = notice
        self.footnote = footnote
    }

    public init(
        configured: [RobotAppSummary],
        cache: RobotAppsCache?,
        snapshot: RobotSnapshotState,
        launch: RobotAppLaunchState?,
        hasKnownRobot: Bool,
        limit: Int,
        at date: Date = Date()
    ) {
        guard hasKnownRobot else {
            self.init(tiles: [], notice: .noRobot)
            return
        }

        // An unconfigured widget shows the robot's own list rather than an empty
        // frame and an instruction: it is useful the moment it lands, and editing
        // it is how someone narrows it down afterwards.
        let source = configured.isEmpty ? (cache?.installed ?? []) : configured
        guard !source.isEmpty else {
            self.init(tiles: [], notice: .noApps)
            return
        }

        let installed = cache?.installed ?? []
        let running = Self.runningName(in: snapshot, at: date)
        let pending = launch?.pending(at: date)

        let tiles = source.prefix(limit).map { summary in
            Tile(
                id: summary.id,
                name: summary.name,
                title: summary.title,
                emoji: summary.emoji,
                gradient: summary.gradient,
                state: Self.state(
                    of: summary,
                    installed: installed,
                    running: running,
                    pending: pending
                )
            )
        }

        self.init(
            tiles: Array(tiles),
            notice: Self.notice(
                launch: launch,
                running: running,
                snapshot: snapshot,
                tiles: tiles,
                at: date
            ),
            footnote: Self.footnote(for: cache, at: date)
        )
    }

    /// Only a fresh reading may name a running app. A stale one is a memory, and
    /// dimming five tiles on the strength of a memory is how a widget stops
    /// working for no visible reason.
    private static func runningName(in snapshot: RobotSnapshotState, at date: Date) -> String? {
        guard case let .fresh(reading) = snapshot else { return nil }
        return reading.runningAppName(at: date)
    }

    private static func runningTitle(in snapshot: RobotSnapshotState, at date: Date) -> String? {
        guard case let .fresh(reading) = snapshot else { return nil }
        return reading.runningAppTitle(at: date)
    }

    private static func state(
        of summary: RobotAppSummary,
        installed: [RobotAppSummary],
        running: String?,
        pending: RobotAppLaunchState.Pending?
    ) -> TileState {
        if let pending, pending.appID == summary.id {
            return pending.isStop ? .stopping : .starting
        }
        guard installed.contains(where: { $0.id == summary.id }) else {
            return .notInstalled
        }
        if let running {
            return running == summary.name ? .running : .blocked
        }
        return .idle
    }

    private static func notice(
        launch: RobotAppLaunchState?,
        running: String?,
        snapshot: RobotSnapshotState,
        tiles: some Collection<Tile>,
        at date: Date
    ) -> Notice {
        // A failure the user caused explains more than a state they can see.
        if let failure = launch?.failure(at: date), launch?.pending(at: date) == nil {
            return .failure(failure.message)
        }
        // Only when the culprit is off-screen: a running tile with a stop badge
        // already says why its neighbours are dimmed.
        if let running, !tiles.contains(where: { $0.name == running }) {
            return .busy(runningTitle(in: snapshot, at: date) ?? running)
        }
        return .none
    }

    private static func footnote(for cache: RobotAppsCache?, at date: Date) -> String? {
        guard let cache, cache.isStale(at: date) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "App list from \(formatter.localizedString(for: cache.takenAt, relativeTo: date))"
    }

    /// Dates at which a timeline must rebuild because a transient statement stops
    /// being true. One millisecond past the inclusive boundary makes the entry
    /// unambiguously expired when WidgetKit renders it with that exact date.
    public static func refreshDates(
        snapshot: RobotSnapshotState,
        launch: RobotAppLaunchState?,
        after now: Date
    ) -> [Date] {
        let afterBoundary: (Date) -> Date = { $0.addingTimeInterval(0.001) }
        var moments: [Date] = []

        if let pending = launch?.pending(at: now) {
            moments.append(afterBoundary(
                pending.since.addingTimeInterval(RobotAppLaunchState.pendingWindow)
            ))
        }
        if let failure = launch?.failure(at: now) {
            moments.append(afterBoundary(
                failure.at.addingTimeInterval(RobotAppLaunchState.failureWindow)
            ))
        }
        if case let .fresh(reading) = snapshot,
           reading.runningAppName(at: now) != nil,
           let expiry = reading.runningAppExpiresAt
        {
            moments.append(afterBoundary(expiry))
        }

        return moments.filter { $0 > now }.sorted()
    }
}
