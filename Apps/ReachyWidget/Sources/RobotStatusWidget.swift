import ReachyKit
import ReachyWidgetUI
import SwiftUI
import WidgetKit

struct RobotStatusEntry: TimelineEntry {
    let date: Date
    let content: RobotWidgetContent
}

/// Reads the snapshot the app left in the shared group. It cannot do anything
/// else: this process is woken for a moment, and a robot is reached over a
/// WebSocket or a peer connection that could not be opened, let alone settled,
/// inside that.
struct RobotStatusProvider: TimelineProvider {
    func placeholder(in _: Context) -> RobotStatusEntry {
        RobotStatusEntry(date: .now, content: RobotWidgetContent(state: .unknown))
    }

    func getSnapshot(in _: Context, completion: @escaping (RobotStatusEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// Two entries, not one. The first is what is true now; the second is the
    /// moment the reading stops being trustworthy, so the widget goes stale on
    /// its own rather than repeating "Awake" for a robot switched off hours ago
    /// while the app is not running to correct it.
    func getTimeline(in _: Context, completion: @escaping (Timeline<RobotStatusEntry>) -> Void) {
        let now = Date.now
        var entries = [entry(at: now)]
        if case let .fresh(snapshot) = RobotSnapshotStore().state(at: now) {
            let expiry = snapshot.takenAt.addingTimeInterval(RobotSnapshotStore.freshness)
            if expiry > now {
                entries.append(RobotStatusEntry(
                    date: expiry,
                    content: RobotWidgetContent(state: .stale(snapshot), at: expiry)
                ))
            }
        }
        // The app reloads timelines when it learns something, so this is only the
        // floor for a phone that never opens it.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60))))
    }

    private func entry(at date: Date) -> RobotStatusEntry {
        let state = RobotSnapshotStore().state(at: date)
        return RobotStatusEntry(date: date, content: RobotWidgetContent(state: state, at: date))
    }
}

struct RobotStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RobotStatus", provider: RobotStatusProvider()) { entry in
            RobotWidgetView(content: entry.content)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(ReachyDeepLink.robot.url)
        }
        .configurationDisplayName("Reachy Mini")
        .description("Your robot's last known state.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
