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
        takenAt: Date? = nil
    ) -> RobotSnapshot {
        RobotSnapshot(
            robotName: name,
            isAwake: isAwake,
            runningApp: runningApp,
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
}
