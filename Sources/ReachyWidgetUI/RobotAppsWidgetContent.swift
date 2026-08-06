import Foundation
import ReachyDesign
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
        /// The app died on the robot. Deliberately not a button: tapping it would
        /// start it again without ever having said what went wrong, and the tap is
        /// worth more falling through to `destination`, where the traceback is.
        case failed
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
            case .starting, .stopping, .blocked, .notInstalled, .failed: false
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
        /// An app died on the robot of its own accord. A tile can say *that* it
        /// failed in one word; only this line has room to say what the daemon said.
        case crashed(app: String, reason: String?)
        case failure(String)

        public var message: String? {
            switch self {
            case .none: nil
            case .noRobot: String(localized: .reachy("No robot. Open Reachy Mini to connect."))
            case .noApps: String(localized: .reachy("No apps yet. Open Reachy Mini to load your robot's apps."))
            case let .busy(title): String(localized: .reachy("“\(title)” is running."))
            case let .crashed(app, reason): Self.crashMessage(app: app, reason: reason)
            case let .failure(reason): reason
            }
        }

        /// Whether tapping the notice is worth suggesting. Everything here is
        /// resolved in the app, so this is only about how loudly to say so.
        public var invitesTheApp: Bool {
            switch self {
            case .none, .busy: false
            case .noRobot, .noApps, .crashed, .failure: true
            }
        }

        /// The daemon's last line is a traceback's worth of detail cut to one
        /// sentence, and it is worth more than the word "error" — but an app that
        /// died without one still has to be reported as having died.
        ///
        /// Closed off with a full stop it rarely brings itself, because the view
        /// appends "Tap to open." straight after: without one the notice reads
        /// "…no module named cv2 Tap to open."
        private static func crashMessage(app: String, reason: String?) -> String {
            guard let reason,
                  !reason.isEmpty else { return String(localized: .reachy("“\(app)” stopped with an error.")) }
            let ends = reason.last.map { ".!?".contains($0) } ?? false
            return String(localized: .reachy("“\(app)” stopped: \(reason)")) + (ends ? "" : ".")
        }
    }

    public let tiles: [Tile]
    public let notice: Notice
    /// Set only once the list is past `RobotAppsCache.freshness`. A menu going old
    /// is worth admitting, not worth refusing to serve.
    public let footnote: String?
    /// Where a tap no tile claimed should land — the widget's own `widgetURL`, and
    /// on iOS 18 the only way it can open the app at all.
    ///
    /// While an app holds the robot, or has just died on it, that app's own page
    /// answers more than the catalogue does: it is where Stop, Restart and the
    /// logs are. Everywhere else the catalogue is the right place to arrive.
    public let destination: ReachyDeepLink

    public init(
        tiles: [Tile],
        notice: Notice = .none,
        footnote: String? = nil,
        destination: ReachyDeepLink = .apps
    ) {
        self.tiles = tiles
        self.notice = notice
        self.footnote = footnote
        self.destination = destination
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
        let reading = AppReading(snapshot, at: date)
        let pending = launch?.pending(at: date)

        let tiles = source.prefix(limit).map { summary in
            Tile(
                id: summary.id,
                name: summary.name,
                title: summary.title,
                emoji: summary.emoji,
                gradient: summary.gradient,
                state: Self.state(of: summary, installed: installed, reading: reading, pending: pending)
            )
        }

        self.init(
            tiles: Array(tiles),
            notice: Self.notice(launch: launch, reading: reading, tiles: tiles, at: date),
            footnote: Self.footnote(for: cache, at: date),
            destination: reading.namesAnApp ? .runningApp : .apps
        )
    }

    /// What a snapshot says about apps, asked once for the tiles and the notice
    /// alike.
    ///
    /// Every field is nil unless the reading is fresh *and* inside its own window —
    /// the running app's and the crash's differ — so nothing below has to remember
    /// to check. A stale reading is a memory, and dimming five tiles on the strength
    /// of a memory is how a widget stops working for no visible reason.
    private struct AppReading {
        var running: String?
        var runningTitle: String?
        var failed: RobotSnapshot.FailedApp?

        init(_ snapshot: RobotSnapshotState, at date: Date) {
            guard case let .fresh(reading) = snapshot else { return }
            running = reading.runningAppName(at: date)
            runningTitle = reading.runningAppTitle(at: date)
            failed = reading.failedApp(at: date)
        }

        /// Whether an app is worth taking a tap to — one holding the robot, or one
        /// that just died on it.
        var namesAnApp: Bool {
            running != nil || failed != nil
        }
    }

    private static func state(
        of summary: RobotAppSummary,
        installed: [RobotAppSummary],
        reading: AppReading,
        pending: RobotAppLaunchState.Pending?
    ) -> TileState {
        if let pending, pending.appID == summary.id {
            return pending.isStop ? .stopping : .starting
        }
        guard installed.contains(where: { $0.id == summary.id }) else {
            return .notInstalled
        }
        // A live app holds the robot; a dead one does not. So running is answered
        // first, and the two can only ever disagree here — one reading writes both.
        if let running = reading.running {
            return running == summary.name ? .running : .blocked
        }
        if reading.failed?.name == summary.name {
            return .failed
        }
        return .idle
    }

    private static func notice(
        launch: RobotAppLaunchState?,
        reading: AppReading,
        tiles: some Collection<Tile>,
        at date: Date
    ) -> Notice {
        // A failure the user caused explains more than a state they can see.
        if let failure = launch?.failure(at: date), launch?.pending(at: date) == nil {
            return .failure(failure.message)
        }
        // Said whether or not the tile is on screen, unlike `busy` below: the tile
        // has room for the word "Failed" and for nothing else, so without this line
        // the reason is nowhere.
        if let failed = reading.failed {
            return .crashed(app: failed.title ?? failed.name, reason: failed.error)
        }
        // Only when the culprit is off-screen: a running tile with a stop badge
        // already says why its neighbours are dimmed.
        if let running = reading.running, !tiles.contains(where: { $0.name == running }) {
            return .busy(reading.runningTitle ?? running)
        }
        return .none
    }

    private static func footnote(for cache: RobotAppsCache?, at date: Date) -> String? {
        guard let cache, cache.isStale(at: date) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return String(
            localized: .reachy("App list from \(formatter.localizedString(for: cache.takenAt, relativeTo: date))")
        )
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
        if case let .fresh(reading) = snapshot,
           reading.failedApp(at: now) != nil,
           let expiry = reading.failedAppExpiresAt
        {
            moments.append(afterBoundary(expiry))
        }

        return moments.filter { $0 > now }.sorted()
    }
}
