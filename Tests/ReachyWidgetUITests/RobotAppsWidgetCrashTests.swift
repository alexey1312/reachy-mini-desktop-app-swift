import Foundation
import ReachyKit
@testable import ReachyWidgetUI
import Testing

/// What the launcher does with an app that died on the robot rather than at the
/// user's hand.
///
/// The gap the running-app dock exposed: the widget's snapshot only ever carried
/// apps that were *busy*, so a crash reached it as "nothing is running" and the
/// tile went quietly back to idle, explaining nothing at all.
@Suite("Reachy Apps widget crashes")
struct RobotAppsWidgetCrashTests {
    private typealias Fixtures = AppsWidgetFixtures

    @Test("a crashed app is marked, and says so")
    func marksACrashedApp() {
        let content = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: nil, failed: Fixtures.dance, error: "ImportError"))
        )

        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .failed)
        #expect(content.notice == .crashed(app: "Dance Party", reason: "ImportError"))
        // Closed off, because the view appends "Tap to open." right behind it.
        #expect(content.notice.message == "“Dance Party” stopped: ImportError.")
    }

    /// A traceback's last line brings its own punctuation about half the time, and
    /// two full stops read as a typo where one reads as a sentence.
    @Test("a reason that ends in a full stop is not given a second one")
    func doesNotDoubleTheFullStop() {
        let reading = Fixtures.snapshot(
            running: nil,
            failed: Fixtures.dance,
            error: "Could not open the camera."
        )

        let content = Fixtures.content(configured: Fixtures.all, snapshot: .fresh(reading))

        #expect(content.notice.message == "“Dance Party” stopped: Could not open the camera.")
    }

    /// A dead process holds nothing. Dimming its neighbours would be the widget
    /// refusing to start anything on behalf of an app that no longer exists.
    @Test("a crash leaves every other tile alone")
    func doesNotBlockOnACrash() {
        let content = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: nil, failed: Fixtures.dance, error: "boom"))
        )

        #expect(content.tiles.filter { $0.name != "dance_party" }.allSatisfy { $0.state == .idle })
        // Mapped rather than `allSatisfy(\.isTappable)`: the key path form is what
        // swiftformat rewrites this to, and `#expect` cannot expand it.
        #expect(content.tiles.filter { $0.name != "dance_party" }.map(\.isTappable).contains(false) == false)
    }

    /// Tapping it would start it again without ever having said what went wrong.
    /// The tap is worth more falling through to the page that carries the logs.
    @Test("a failed tile is not a button, and sends the tap to the app's own page")
    func routesACrashToTheRunningAppPage() {
        let crashed = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: nil, failed: Fixtures.dance, error: "boom"))
        )

        let running = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: Fixtures.dance))
        )

        #expect(crashed.tiles.first { $0.name == "dance_party" }?.isTappable == false)
        #expect(crashed.destination == .runningApp)
        #expect(running.destination == .runningApp)
        // Nothing to open but the catalogue.
        #expect(Fixtures.content(configured: Fixtures.all).destination == .apps)
    }

    @Test("an app that died without a reason still says it died")
    func reportsACrashWithoutAReason() {
        let content = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: nil, failed: Fixtures.dance))
        )

        #expect(content.notice.message == "“Dance Party” stopped with an error.")
        #expect(content.notice.invitesTheApp)
    }

    /// Nothing will ever arrive to say the crash is over, so it expires on its own
    /// — and sooner than the reading that carries it.
    @Test("an old crash stops being reported while the reading is still fresh")
    func forgetsAnOldCrash() {
        let taken = Fixtures.now.addingTimeInterval(-RobotSnapshotStore.failureFreshness - 1)
        let reading = Fixtures.snapshot(running: nil, failed: Fixtures.dance, error: "boom", takenAt: taken)

        let content = Fixtures.content(configured: Fixtures.all, snapshot: .fresh(reading))

        #expect(content.tiles.allSatisfy { $0.state == .idle })
        #expect(content.notice == .none)
        #expect(content.destination == .apps)
    }

    /// The user's own failed tap is the more recent news, and the one they are
    /// waiting on an answer for.
    @Test("a launch that just failed outranks a crash from before it")
    func prefersALaunchFailureToACrash() {
        let launch = RobotAppLaunchState(
            failure: .init(appID: Fixtures.chess.id, message: "Could not connect to the server.", at: Fixtures.now)
        )

        let content = Fixtures.content(
            configured: Fixtures.all,
            snapshot: .fresh(Fixtures.snapshot(running: nil, failed: Fixtures.dance, error: "boom")),
            launch: launch
        )

        #expect(content.notice == .failure("Could not connect to the server."))
        // The tile still carries it — only the one notice line had to choose.
        #expect(content.tiles.first { $0.name == "dance_party" }?.state == .failed)
    }
}
