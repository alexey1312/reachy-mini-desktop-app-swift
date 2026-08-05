import Foundation
import ReachyKit
@testable import ReachyWidgetUI
import Testing

/// Every decision the launcher makes lives here rather than in the view, so this
/// is where the rules are actually checked: which apps show, which are tappable,
/// and — the one that matters most — when the widget is entitled to say an app is
/// running at all.
@Suite("Reachy Apps widget content")
struct RobotAppsWidgetContentTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private let dance = RobotAppSummary(id: "pollen/dance", name: "dance_party", title: "Dance Party")
    private let faces = RobotAppSummary(id: "pollen/faces", name: "face_tracking", title: "Face Tracking")
    private let chess = RobotAppSummary(id: "pollen/chess", name: "chess", title: "Chess")

    private var all: [RobotAppSummary] {
        [dance, faces, chess]
    }

    private func cache(_ installed: [RobotAppSummary]? = nil, takenAt: Date? = nil) -> RobotAppsCache {
        RobotAppsCache(installed: installed ?? all, takenAt: takenAt ?? now)
    }

    private func snapshot(running: RobotAppSummary?, takenAt: Date? = nil) -> RobotSnapshot {
        RobotSnapshot(
            robotName: "kitchen",
            isAwake: true,
            runningApp: running?.title,
            runningAppName: running?.name,
            takenAt: takenAt ?? now
        )
    }

    private func content(
        configured: [RobotAppSummary] = [],
        cache: RobotAppsCache? = nil,
        snapshot: RobotSnapshotState = .unknown,
        launch: RobotAppLaunchState? = nil,
        hasKnownRobot: Bool = true,
        limit: Int = 4,
        at date: Date? = nil
    ) -> RobotAppsWidgetContent {
        RobotAppsWidgetContent(
            configured: configured,
            cache: cache ?? self.cache(),
            snapshot: snapshot,
            launch: launch,
            hasKnownRobot: hasKnownRobot,
            limit: limit,
            at: date ?? now
        )
    }

    // MARK: - Which apps show

    /// A widget just dropped on the Home Screen is useful before anyone edits it.
    @Test("an unconfigured widget shows the robot's own list")
    func fallsBackToTheInstalledList() {
        let content = content(configured: [], limit: 2)

        #expect(content.tiles.map(\.name) == ["dance_party", "face_tracking"])
    }

    @Test("a configured widget shows what was chosen, in order")
    func showsTheConfiguredApps() {
        let content = content(configured: [chess, dance])

        #expect(content.tiles.map(\.name) == ["chess", "dance_party"])
    }

    @Test("each family takes only as many as it can draw", arguments: [2, 4, 8])
    func truncatesToTheFamily(limit: Int) {
        let content = content(configured: all, limit: limit)

        #expect(content.tiles.count == min(limit, all.count))
    }

    @Test("no known robot means no tiles, however full the cache is")
    func showsNothingWithoutARobot() {
        let content = content(configured: all, hasKnownRobot: false)

        #expect(content.tiles.isEmpty)
        #expect(content.notice == .noRobot)
    }

    @Test("a robot whose apps were never listed says so")
    func reportsAnEmptyCache() {
        let content = content(cache: cache([]))

        #expect(content.tiles.isEmpty)
        #expect(content.notice == .noApps)
    }

    // MARK: - Tile states

    @Test("nothing running means every tile is ready")
    func marksIdleTiles() {
        let content = content(configured: all, snapshot: .fresh(snapshot(running: nil)))

        #expect(content.tiles.allSatisfy { $0.state == .idle })
        #expect(content.tiles.map(\.isTappable).contains(false) == false)
    }

    @Test("the running app is marked, and its neighbours are blocked")
    func marksTheRunningApp() {
        let content = content(configured: all, snapshot: .fresh(snapshot(running: dance)))

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .running)
        #expect(content.tiles.filter { $0.name != "dance_party" }.allSatisfy { $0.state == .blocked })
    }

    /// The Apps screen disables Start while something runs, and a widget that
    /// evicted silently would be the one place in the app that does not.
    @Test("a blocked tile is not a button")
    func blockedTilesDoNotTap() {
        let content = content(configured: all, snapshot: .fresh(snapshot(running: dance)))

        #expect(content.tiles.first { $0.name == "chess" }?.isTappable == false)
        #expect(content.tiles.first { $0.name == "dance_party" }?.isTappable == true)
    }

    /// The rule the whole type exists for. A robot switched off tells nobody, so
    /// past the window the widget stops claiming to know what it is running —
    /// which also means it stops dimming four tiles on the strength of a memory.
    @Test("a stale reading claims nothing is running")
    func refusesToClaimARunningAppFromAStaleReading() {
        let taken = now.addingTimeInterval(-RobotSnapshotStore.freshness - 1)
        let stale = snapshot(running: dance, takenAt: taken)

        let fresh = content(configured: all, snapshot: .fresh(stale))
        let expired = content(configured: all, snapshot: .stale(stale))

        #expect(fresh.tiles.first { $0.name == "dance_party" }?.state == .running)
        #expect(expired.tiles.allSatisfy { $0.state == .idle })
    }

    @Test("an app that is gone from the robot stays visible but inert")
    func marksAnUninstalledApp() {
        let content = content(configured: all, cache: cache([dance, faces]))

        let tile = content.tiles.first { $0.name == "chess" }
        #expect(tile?.state == .notInstalled)
        #expect(tile?.isTappable == false)
    }

    // MARK: - A tap in flight

    @Test("a tap that has not come back yet reads as starting")
    func marksAPendingStart() {
        let launch = RobotAppLaunchState(pending: .init(appID: dance.id, isStop: false, since: now))

        let content = content(configured: all, launch: launch)

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .starting)
    }

    @Test("a stop in flight reads as stopping, not starting")
    func marksAPendingStop() {
        let launch = RobotAppLaunchState(pending: .init(appID: dance.id, isStop: true, since: now))

        let content = content(configured: all, launch: launch)

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .stopping)
    }

    /// The extension can be killed mid-call, and then nothing ever clears the
    /// caption. The window is what does instead.
    @Test("a launch that never came back stops claiming to be in flight")
    func expiresAStuckLaunch() {
        let since = now.addingTimeInterval(-RobotAppLaunchState.pendingWindow - 1)
        let launch = RobotAppLaunchState(pending: .init(appID: dance.id, isStop: false, since: since))

        let content = content(configured: all, launch: launch)

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .idle)
    }

    // MARK: - Notices

    @Test("a failed launch carries the daemon's own sentence")
    func reportsAFailure() {
        let launch = RobotAppLaunchState(
            failure: .init(appID: dance.id, message: "Could not connect to the server.", at: now)
        )

        let content = content(configured: all, launch: launch)

        #expect(content.notice == .failure("Could not connect to the server."))
        #expect(content.notice.invitesTheApp)
    }

    @Test("an old failure stops being reported")
    func forgetsAnOldFailure() {
        let at = now.addingTimeInterval(-RobotAppLaunchState.failureWindow - 1)
        let launch = RobotAppLaunchState(failure: .init(appID: dance.id, message: "Nope", at: at))

        #expect(content(configured: all, launch: launch).notice == .none)
    }

    /// A running tile with a stop badge already explains why its neighbours are
    /// dimmed. A notice is only needed when the culprit is off-screen.
    @Test("the robot being busy is only announced when nothing on screen shows it")
    func announcesAnOffscreenRunningApp() {
        let visible = content(configured: all, snapshot: .fresh(snapshot(running: dance)))
        let hidden = content(configured: [faces, chess], snapshot: .fresh(snapshot(running: dance)))

        #expect(visible.notice == .none)
        #expect(hidden.notice == .busy("Dance Party"))
    }

    // MARK: - Staleness

    /// A stale reading is a lie; a stale menu is merely old. So the list still
    /// renders and still launches — it just says how old it is.
    @Test("an old app list still shows, with a footnote")
    func footnotesAnOldList() {
        let taken = now.addingTimeInterval(-RobotAppsCache.freshness - 1)

        let old = content(configured: [], cache: cache(takenAt: taken))
        let current = content(configured: [], cache: cache())

        #expect(old.tiles.isEmpty == false)
        #expect(old.tiles.map(\.isTappable).contains(false) == false)
        #expect(old.footnote?.isEmpty == false)
        #expect(current.footnote == nil)
    }
}
