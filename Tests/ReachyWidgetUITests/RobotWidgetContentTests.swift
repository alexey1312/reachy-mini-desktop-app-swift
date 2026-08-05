import Foundation
import ReachyKit
@testable import ReachyWidgetUI
import Testing

/// The widget's whole job is to say something true about a robot nobody is
/// currently talking to. What it must never do is state a reading it cannot
/// stand behind.
@Suite("Robot widget content")
struct RobotWidgetContentTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        name: String? = "kitchen",
        isAwake: Bool = true,
        runningApp: String? = nil,
        ageInMinutes: Double = 0
    ) -> RobotSnapshot {
        RobotSnapshot(
            robotName: name,
            isAwake: isAwake,
            runningApp: runningApp,
            takenAt: now.addingTimeInterval(-ageInMinutes * 60)
        )
    }

    @Test("with no robot ever connected it offers the app rather than a state")
    func describesTheEmptyState() {
        let content = RobotWidgetContent(state: .unknown, at: now)

        #expect(content.isStale == false)
        #expect(content.detail.localizedCaseInsensitiveContains("awake") == false)
        #expect(content.detail.localizedCaseInsensitiveContains("asleep") == false)
    }

    @Test("a fresh reading is stated in the present tense")
    func describesAnAwakeRobot() {
        let content = RobotWidgetContent(state: .fresh(snapshot()), at: now)

        #expect(content.title == "kitchen")
        #expect(content.detail.localizedCaseInsensitiveContains("awake"))
        #expect(content.isStale == false)
    }

    @Test("an asleep robot says so")
    func describesASleepingRobot() {
        let content = RobotWidgetContent(state: .fresh(snapshot(isAwake: false)), at: now)

        #expect(content.detail.localizedCaseInsensitiveContains("asleep"))
    }

    /// The one rule worth a test of its own: past the window the widget reports
    /// when it last looked, never what the robot is doing. A robot switched off
    /// an hour ago would otherwise still read as awake.
    @Test("a stale reading reports when it was taken, not what the robot is doing")
    func refusesToStateAStaleReading() {
        let content = RobotWidgetContent(state: .stale(snapshot(ageInMinutes: 120)), at: now)

        #expect(content.isStale)
        #expect(content.title == "kitchen")
        #expect(content.detail.localizedCaseInsensitiveContains("awake") == false)
        #expect(content.detail.localizedCaseInsensitiveContains("asleep") == false)
    }

    /// Daemon 1.9.0 cannot be renamed and reports an empty name, so a robot
    /// without one is the common case rather than an edge.
    @Test("a robot with no name still has something to be called")
    func namesAnUnnamedRobot() {
        let content = RobotWidgetContent(state: .fresh(snapshot(name: nil)), at: now)

        #expect(content.title.isEmpty == false)
    }

    /// The running app is the most useful thing on the widget when there is one,
    /// and it belongs in front of the plain awake/asleep reading.
    @Test("a running app is named instead of the plain state")
    func namesTheRunningApp() {
        let content = RobotWidgetContent(state: .fresh(snapshot(runningApp: "Hand Tracker")), at: now)

        #expect(content.detail.contains("Hand Tracker"))
    }
}
