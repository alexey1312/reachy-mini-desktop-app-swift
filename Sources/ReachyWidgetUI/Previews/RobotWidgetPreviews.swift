import ReachyKit
import ReachyWidgetUI
import SwiftUI

/// Every date here is fixed. The stale state renders a relative time, and taking
/// it from `Date()` would move the reference image on every run.
let robotWidgetPreviewDate = Date(timeIntervalSince1970: 1_800_000_000)

func robotWidgetPreviewCard(_ content: RobotWidgetContent) -> some View {
    RobotWidgetView(content: content)
        .padding()
        // A small widget's own size, so the preview shows what the user gets
        // rather than a view stretched over a device.
        .frame(width: 158, height: 158)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
}

#Preview("Widget — no robot", traits: .sizeThatFitsLayout) {
    robotWidgetPreviewCard(RobotWidgetContent(state: .unknown, at: robotWidgetPreviewDate))
}

#Preview("Widget — awake", traits: .sizeThatFitsLayout) {
    robotWidgetPreviewCard(RobotWidgetContent(
        state: .fresh(RobotSnapshot(
            robotName: "kitchen",
            isAwake: true,
            runningApp: nil,
            takenAt: robotWidgetPreviewDate
        )),
        at: robotWidgetPreviewDate
    ))
}

#Preview("Widget — asleep", traits: .sizeThatFitsLayout) {
    robotWidgetPreviewCard(RobotWidgetContent(
        state: .fresh(RobotSnapshot(
            robotName: "kitchen",
            isAwake: false,
            runningApp: nil,
            takenAt: robotWidgetPreviewDate
        )),
        at: robotWidgetPreviewDate
    ))
}

#Preview("Widget — running an app", traits: .sizeThatFitsLayout) {
    robotWidgetPreviewCard(RobotWidgetContent(
        state: .fresh(RobotSnapshot(
            robotName: "kitchen",
            isAwake: true,
            runningApp: "Hand Tracker",
            takenAt: robotWidgetPreviewDate
        )),
        at: robotWidgetPreviewDate
    ))
}

// An app that died on its own. Falling back to "Awake" here would be the widget
// pretending nothing happened.
#Preview("Widget — app crashed", traits: .sizeThatFitsLayout) {
    robotWidgetPreviewCard(RobotWidgetContent(
        state: .fresh(RobotSnapshot(
            robotName: "kitchen",
            isAwake: true,
            runningApp: nil,
            failedApp: .init(name: "hand_tracker", title: "Hand Tracker", error: "ImportError: no module named cv2"),
            runningAppTakenAt: robotWidgetPreviewDate,
            takenAt: robotWidgetPreviewDate
        )),
        at: robotWidgetPreviewDate
    ))
}

// The state the widget spends most of its life in: nobody has opened the app for
// a while, so it reports when it last looked instead of what the robot is doing.
#Preview("Widget — last seen", traits: .sizeThatFitsLayout) {
    robotWidgetPreviewCard(RobotWidgetContent(
        state: .stale(RobotSnapshot(
            robotName: "kitchen",
            isAwake: true,
            runningApp: nil,
            takenAt: robotWidgetPreviewDate
        )),
        at: robotWidgetPreviewDate.addingTimeInterval(2 * 60 * 60)
    ))
}

// Daemon 1.9.0 reports an empty name and cannot be renamed, so this is what most
// robots actually look like.
#Preview("Widget — unnamed robot", traits: .sizeThatFitsLayout) {
    robotWidgetPreviewCard(RobotWidgetContent(
        state: .fresh(RobotSnapshot(robotName: nil, isAwake: true, runningApp: nil, takenAt: robotWidgetPreviewDate)),
        at: robotWidgetPreviewDate
    ))
}
