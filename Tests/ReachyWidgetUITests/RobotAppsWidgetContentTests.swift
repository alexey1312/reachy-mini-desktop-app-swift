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
    private typealias Fixtures = AppsWidgetFixtures

    // MARK: - Which apps show

    /// A widget just dropped on the Home Screen is useful before anyone edits it.
    @Test("an unconfigured widget shows the robot's own list")
    func fallsBackToTheInstalledList() {
        let content = Fixtures.content(configured: [], limit: 2)

        #expect(content.tiles.map(\.name) == ["dance_party", "face_tracking"])
    }

    @Test("a configured widget shows what was chosen, in order")
    func showsTheConfiguredApps() {
        let content = Fixtures.content(configured: [Fixtures.chess, Fixtures.dance])

        #expect(content.tiles.map(\.name) == ["chess", "dance_party"])
    }

    @Test("each family takes only as many as it can draw", arguments: [2, 4, 8])
    func truncatesToTheFamily(limit: Int) {
        let content = Fixtures.content(configured: Fixtures.all, limit: limit)

        #expect(content.tiles.count == min(limit, Fixtures.all.count))
    }

    @Test("no known robot means no tiles, however full the cache is")
    func showsNothingWithoutARobot() {
        let content = Fixtures.content(configured: Fixtures.all, hasKnownRobot: false)

        #expect(content.tiles.isEmpty)
        #expect(content.notice == .noRobot)
    }

    @Test("a robot whose apps were never listed says so")
    func reportsAnEmptyCache() {
        let content = Fixtures.content(cache: Fixtures.cache([]))

        #expect(content.tiles.isEmpty)
        #expect(content.notice == .noApps)
    }

    // MARK: - Tile states

    @Test("nothing running means every tile is ready")
    func marksIdleTiles() {
        let content = Fixtures.content(configured: Fixtures.all, snapshot: .fresh(Fixtures.snapshot(running: nil)))

        #expect(content.tiles.allSatisfy { $0.state == .idle })
        #expect(content.tiles.map(\.isTappable).contains(false) == false)
    }

    @Test("the running app is marked, and its neighbours are blocked")
    func marksTheRunningApp() {
        let content = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: Fixtures.dance))
        )

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .running)
        #expect(content.tiles.filter { $0.name != "dance_party" }.allSatisfy { $0.state == .blocked })
    }

    /// The Apps screen disables Start while something runs, and a widget that
    /// evicted silently would be the one place in the app that does not.
    @Test("a blocked tile is not a button")
    func blockedTilesDoNotTap() {
        let content = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: Fixtures.dance))
        )

        #expect(content.tiles.first { $0.name == "chess" }?.isTappable == false)
        #expect(content.tiles.first { $0.name == "dance_party" }?.isTappable == true)
    }

    /// The rule the whole type exists for. A robot switched off tells nobody, so
    /// past the window the widget stops claiming to know what it is running —
    /// which also means it stops dimming four tiles on the strength of a memory.
    @Test("a stale reading claims nothing is running")
    func refusesToClaimARunningAppFromAStaleReading() {
        let taken = Fixtures.now.addingTimeInterval(-RobotSnapshotStore.freshness - 1)
        let stale = Fixtures.snapshot(running: Fixtures.dance, takenAt: taken, runningAppTakenAt: Fixtures.now)

        let fresh = Fixtures.content(configured: Fixtures.all, snapshot: .fresh(stale))
        let expired = Fixtures.content(configured: Fixtures.all, snapshot: .stale(stale))

        #expect(fresh.tiles.first { $0.name == "dance_party" }?.state == .running)
        #expect(expired.tiles.allSatisfy { $0.state == .idle })
    }

    @Test("an app that is gone from the robot stays visible but inert")
    func marksAnUninstalledApp() {
        let content = Fixtures.content(
            configured: Fixtures.all,
            cache: Fixtures.cache([Fixtures.dance, Fixtures.faces])
        )

        let tile = content.tiles.first { $0.name == "chess" }
        #expect(tile?.state == .notInstalled)
        #expect(tile?.isTappable == false)
    }

    // MARK: - A tap in flight

    @Test("a tap that has not come back yet reads as starting")
    func marksAPendingStart() {
        let launch = RobotAppLaunchState(pending: .init(appID: Fixtures.dance.id, isStop: false, since: Fixtures.now))

        let content = Fixtures.content(configured: Fixtures.all, launch: launch)

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .starting)
    }

    @Test("a stop in flight reads as stopping, not starting")
    func marksAPendingStop() {
        let launch = RobotAppLaunchState(pending: .init(appID: Fixtures.dance.id, isStop: true, since: Fixtures.now))

        let content = Fixtures.content(configured: Fixtures.all, launch: launch)

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .stopping)
    }

    /// The extension can be killed mid-call, and then nothing ever clears the
    /// caption. The window is what does instead.
    @Test("a launch that never came back stops claiming to be in flight")
    func expiresAStuckLaunch() {
        let since = Fixtures.now.addingTimeInterval(-RobotAppLaunchState.pendingWindow - 1)
        let launch = RobotAppLaunchState(pending: .init(appID: Fixtures.dance.id, isStop: false, since: since))

        let content = Fixtures.content(configured: Fixtures.all, launch: launch)

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .idle)
    }

    // MARK: - Notices

    @Test("a failed launch carries the daemon's own sentence")
    func reportsAFailure() {
        let launch = RobotAppLaunchState(
            failure: .init(appID: Fixtures.dance.id, message: "Could not connect to the server.", at: Fixtures.now)
        )

        let content = Fixtures.content(configured: Fixtures.all, launch: launch)

        #expect(content.notice == .failure("Could not connect to the server."))
        #expect(content.notice.invitesTheApp)
    }

    @Test("an old failure stops being reported")
    func forgetsAnOldFailure() {
        let at = Fixtures.now.addingTimeInterval(-RobotAppLaunchState.failureWindow - 1)
        let launch = RobotAppLaunchState(failure: .init(appID: Fixtures.dance.id, message: "Nope", at: at))

        #expect(Fixtures.content(configured: Fixtures.all, launch: launch).notice == .none)
    }

    /// A running tile with a stop badge already explains why its neighbours are
    /// dimmed. A notice is only needed when the culprit is off-screen.
    @Test("the robot being busy is only announced when nothing on screen shows it")
    func announcesAnOffscreenRunningApp() {
        let visible = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: Fixtures.dance))
        )
        let hidden = Fixtures.content(
            configured: [Fixtures.faces, Fixtures.chess],
            snapshot: .fresh(Fixtures.snapshot(running: Fixtures.dance))
        )

        #expect(visible.notice == .none)
        #expect(hidden.notice == .busy("Dance Party"))
    }

    // MARK: - Staleness

    /// A stale reading is a lie; a stale menu is merely old. So the list still
    /// renders and still launches — it just says how old it is.
    @Test("an old app list still shows, with a footnote")
    func footnotesAnOldList() {
        let taken = Fixtures.now.addingTimeInterval(-RobotAppsCache.freshness - 1)

        let old = Fixtures.content(configured: [], cache: Fixtures.cache(takenAt: taken))
        let current = Fixtures.content(configured: [], cache: Fixtures.cache())

        #expect(old.tiles.isEmpty == false)
        #expect(old.tiles.map(\.isTappable).contains(false) == false)
        #expect(old.footnote?.isEmpty == false)
        #expect(current.footnote == nil)
    }

    @Test("a running app expires even while the daemon reading stays fresh")
    func expiresTheRunningAppIndependently() {
        let appReading = Fixtures.now.addingTimeInterval(-RobotSnapshotStore.freshness - 1)
        let reading = RobotSnapshot(
            robotID: "robot",
            robotName: "kitchen",
            isAwake: true,
            runningApp: Fixtures.dance.title,
            runningAppName: Fixtures.dance.name,
            runningAppTakenAt: appReading,
            takenAt: Fixtures.now
        )

        let content = Fixtures.content(configured: Fixtures.all, snapshot: .fresh(reading))

        #expect(content.tiles.allSatisfy { $0.state == .idle })
    }

    @Test("timeline refreshes just after every inclusive expiry")
    func schedulesTransientExpiries() throws {
        let reading = Fixtures.snapshot(running: Fixtures.dance)
        let appExpiry = try #require(reading.runningAppExpiresAt)
        let launch = RobotAppLaunchState(
            failure: .init(appID: Fixtures.dance.id, message: "Nope", at: Fixtures.now)
        )

        let failureDates = RobotAppsWidgetContent.refreshDates(
            snapshot: .fresh(reading),
            launch: launch,
            after: Fixtures.now
        )
        let pendingDates = RobotAppsWidgetContent.refreshDates(
            snapshot: .fresh(reading),
            launch: RobotAppLaunchState(
                pending: .init(appID: Fixtures.dance.id, isStop: false, since: Fixtures.now)
            ),
            after: Fixtures.now
        )

        #expect(failureDates.count == 2)
        #expect(failureDates.contains { $0 > appExpiry })
        #expect(failureDates.contains {
            $0 > Fixtures.now.addingTimeInterval(RobotAppLaunchState.failureWindow)
        })
        #expect(pendingDates.count == 2)
        #expect(pendingDates.contains {
            $0 > Fixtures.now.addingTimeInterval(RobotAppLaunchState.pendingWindow)
        })
    }

    /// Without this the tile would carry a warning badge for half an hour, and the
    /// notice a traceback the user has long since stopped caring about — with no
    /// app running to correct either.
    @Test("a crash schedules its own, earlier refresh")
    func schedulesTheCrashExpiry() throws {
        let reading = Fixtures.snapshot(running: nil, failed: Fixtures.dance, error: "boom")
        let expiry = try #require(reading.failedAppExpiresAt)

        let dates = RobotAppsWidgetContent.refreshDates(snapshot: .fresh(reading), launch: nil, after: Fixtures.now)

        #expect(dates.count == 1)
        #expect(dates[0] > expiry)
        #expect(dates[0] < Fixtures.now.addingTimeInterval(RobotSnapshotStore.freshness))
    }
}
