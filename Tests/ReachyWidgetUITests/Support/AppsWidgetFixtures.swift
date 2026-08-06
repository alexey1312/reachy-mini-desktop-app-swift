import Foundation
import ReachyKit
@testable import ReachyWidgetUI

/// The robot, the menu and the reading every launcher test builds its content
/// from — shared because the rules split across more than one suite, and a second
/// copy of them is a second thing to keep in step.
enum AppsWidgetFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let dance = RobotAppSummary(id: "pollen/dance", name: "dance_party", title: "Dance Party")
    static let faces = RobotAppSummary(id: "pollen/faces", name: "face_tracking", title: "Face Tracking")
    static let chess = RobotAppSummary(id: "pollen/chess", name: "chess", title: "Chess")

    static var all: [RobotAppSummary] {
        [dance, faces, chess]
    }

    static func cache(_ installed: [RobotAppSummary]? = nil, takenAt: Date? = nil) -> RobotAppsCache {
        RobotAppsCache(robotID: "robot", installed: installed ?? all, takenAt: takenAt ?? now)
    }

    /// One reading of one question: an app is running, or one died, or neither.
    /// `runningAppTakenAt` is what both expire against, so it is set whenever
    /// either is.
    static func snapshot(
        running: RobotAppSummary?,
        failed: RobotAppSummary? = nil,
        error: String? = nil,
        takenAt: Date? = nil,
        runningAppTakenAt: Date? = nil
    ) -> RobotSnapshot {
        let sawAnApp = running != nil || failed != nil
        return RobotSnapshot(
            robotName: "kitchen",
            isAwake: true,
            runningApp: running?.title,
            runningAppName: running?.name,
            failedApp: failed.map { .init(name: $0.name, title: $0.title, error: error) },
            runningAppTakenAt: sawAnApp ? (runningAppTakenAt ?? takenAt ?? now) : nil,
            takenAt: takenAt ?? now
        )
    }

    static func content(
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
            cache: cache ?? Self.cache(),
            snapshot: snapshot,
            launch: launch,
            hasKnownRobot: hasKnownRobot,
            limit: limit,
            at: date ?? now
        )
    }
}
