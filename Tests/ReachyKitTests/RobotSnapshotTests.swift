import Foundation
@testable import ReachyKit
import Testing

/// The widget renders what the app last saw, because a widget extension lives for
/// seconds and cannot connect to anything itself. Everything here exists to keep
/// that honest: what was seen, and how long ago.
@Suite("Robot snapshot")
struct RobotSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store() throws -> RobotSnapshotStore {
        try RobotSnapshotStore(
            defaults: #require(UserDefaults(suiteName: "RobotSnapshotTests.\(UUID().uuidString)"))
        )
    }

    private func snapshot(
        name: String? = "kitchen",
        isAwake: Bool = true,
        runningApp: String? = nil,
        runningAppName: String? = nil,
        takenAt: Date? = nil
    ) -> RobotSnapshot {
        RobotSnapshot(
            robotName: name,
            isAwake: isAwake,
            runningApp: runningApp,
            runningAppName: runningAppName,
            takenAt: takenAt ?? now
        )
    }

    @Test("a written snapshot comes back")
    func roundTrips() throws {
        let store = try store()
        let written = snapshot(runningApp: "Hand Tracker")

        store.write(written)

        #expect(store.current == written)
    }

    /// The state before a robot has ever been connected. A widget cannot invent
    /// one, and pretending otherwise is the whole failure mode here.
    @Test("an empty store knows nothing")
    func startsUnknown() throws {
        let store = try store()

        #expect(store.current == nil)
        #expect(store.state(at: now) == .unknown)
    }

    @Test("a snapshot just taken is fresh")
    func reportsFresh() throws {
        let store = try store()
        let written = snapshot()
        store.write(written)

        #expect(store.state(at: now.addingTimeInterval(60)) == .fresh(written))
    }

    /// A robot switched off does not tell anyone. Past the window the app stops
    /// claiming to know what it is doing and says only when it last looked.
    @Test("a snapshot past the freshness window is stale, not wrong")
    func reportsStale() throws {
        let store = try store()
        let written = snapshot()
        store.write(written)

        #expect(store.state(at: now.addingTimeInterval(RobotSnapshotStore.freshness + 1)) == .stale(written))
    }

    /// Exactly at the boundary still counts as fresh — the window is how long the
    /// reading is trusted for, inclusive.
    @Test("the freshness window is inclusive at its edge")
    func treatsTheBoundaryAsFresh() throws {
        let store = try store()
        let written = snapshot()
        store.write(written)

        #expect(store.state(at: now.addingTimeInterval(RobotSnapshotStore.freshness)) == .fresh(written))
    }

    /// A clock that went backwards — a timezone change, a manual correction —
    /// must not read as a reading from the future being stale.
    @Test("a snapshot dated in the future is still fresh")
    func toleratesAClockGoingBackwards() throws {
        let store = try store()
        let written = snapshot()
        store.write(written)

        #expect(store.state(at: now.addingTimeInterval(-600)) == .fresh(written))
    }

    /// Disconnecting clears it. Leaving the last reading behind would have the
    /// widget describe a robot the user deliberately let go of.
    @Test("clearing the snapshot returns to knowing nothing")
    func clears() throws {
        let store = try store()
        store.write(snapshot())

        store.clear()

        #expect(store.current == nil)
        #expect(store.state(at: now) == .unknown)
    }

    /// A reading written by a build that predates `runningAppName` must survive an
    /// update, not throw. A literal blob rather than a re-encode: encoding with
    /// today's type would put the field back and prove nothing.
    @Test("a snapshot written before the running app had a name still decodes")
    func decodesABlobWithoutTheName() throws {
        let defaults = try #require(UserDefaults(suiteName: "RobotSnapshotTests.\(UUID().uuidString)"))
        let legacy = """
        {"robotName":"kitchen","isAwake":true,"takenAt":\(now.timeIntervalSinceReferenceDate)}
        """
        defaults.set(Data(legacy.utf8), forKey: RobotSnapshotStore.key)

        let current = try #require(RobotSnapshotStore(defaults: defaults).current)

        #expect(current.robotName == "kitchen")
        #expect(current.isAwake)
        #expect(current.runningApp == nil)
        #expect(current.runningAppName == nil)
        #expect(current.takenAt == now)
    }

    /// Whoever learned this only re-checked one field, so the rest of the reading
    /// has to survive.
    @Test("recording a running app keeps the rest of the reading")
    func recordsARunningApp() throws {
        let store = try store()
        store.write(snapshot(takenAt: now.addingTimeInterval(-300)))

        store.recordRunningApp(title: "Dance Party", name: "reachy_mini_dance", at: now)

        let current = try #require(store.current)
        #expect(current.robotName == "kitchen")
        #expect(current.isAwake)
        #expect(current.runningApp == "Dance Party")
        #expect(current.runningAppName == "reachy_mini_dance")
        // The caller had just spoken to the robot, so the reading is that fresh.
        #expect(current.takenAt == now)
    }

    /// Nothing running is a fact, not an absence of one.
    @Test("recording no running app clears the last one")
    func clearsARunningApp() throws {
        let store = try store()
        store.write(snapshot(runningApp: "Dance Party", runningAppName: "reachy_mini_dance"))

        store.recordRunningApp(title: nil, name: nil, at: now)

        let current = try #require(store.current)
        #expect(current.runningApp == nil)
        #expect(current.runningAppName == nil)
        #expect(current.robotName == "kitchen")
    }

    @Test("recording a running app with nothing to merge into still writes one")
    func recordsWithoutAPriorReading() throws {
        let store = try store()

        store.recordRunningApp(title: "Dance Party", name: "reachy_mini_dance", at: now)

        let current = try #require(store.current)
        #expect(current.robotName == nil)
        #expect(current.runningApp == "Dance Party")
        #expect(store.state(at: now) == .fresh(current))
    }

    @Test("a caller that learned the motor state passes it through")
    func recordsAwakeness() throws {
        let store = try store()
        store.write(snapshot(isAwake: true))

        store.recordRunningApp(title: nil, name: nil, isAwake: false, at: now)

        #expect(store.current?.isAwake == false)
    }
}
