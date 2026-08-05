import AppIntents
import ReachyKit
import ReachyWidgetUI
import SwiftUI
import WidgetKit

struct ReachyAppsEntry: TimelineEntry {
    let date: Date
    let content: RobotAppsWidgetContent
}

/// Reads the app group and nothing else, exactly like `RobotStatusProvider`.
///
/// The live list belongs to `RobotAppQuery`, which the system runs only while
/// someone is editing the widget — a timeline is built far too often, and far too
/// silently, to spend a robot round trip on.
struct ReachyAppsProvider: AppIntentTimelineProvider {
    /// How many tiles each family can draw legibly. The configuration may hold
    /// more (it was edited on a larger widget, or the picker allowed it), so this
    /// truncates rather than assumes.
    private func limit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 2
        case .systemLarge: 8
        default: 4
        }
    }

    func placeholder(in context: Context) -> ReachyAppsEntry {
        entry(at: .now, apps: nil, limit: limit(for: context.family))
    }

    func snapshot(for configuration: RobotAppsConfigurationIntent, in context: Context) async -> ReachyAppsEntry {
        entry(at: .now, apps: configuration.apps, limit: limit(for: context.family))
    }

    /// More than one entry, so the widget corrects itself while the app is not
    /// running to correct it: a launch that never came back stops saying
    /// "Starting…", and a reading past its window stops dimming every tile but
    /// one.
    func timeline(
        for configuration: RobotAppsConfigurationIntent,
        in context: Context
    ) async -> Timeline<ReachyAppsEntry> {
        let now = Date.now
        let limit = limit(for: context.family)
        var entries = [entry(at: now, apps: configuration.apps, limit: limit)]

        for moment in expiries(after: now) {
            entries.append(entry(at: moment, apps: configuration.apps, limit: limit))
        }

        // The app reloads timelines when it learns something, and so does the
        // toggle intent — this is only the floor for a phone that never opens it.
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60)))
    }

    /// The moments something on screen stops being true, in order.
    private func expiries(after now: Date) -> [Date] {
        var moments: [Date] = []
        if let pending = RobotAppLaunchStateStore().current?.pending(at: now) {
            moments.append(pending.since.addingTimeInterval(RobotAppLaunchState.pendingWindow))
        }
        if case let .fresh(reading) = RobotSnapshotStore().state(at: now), reading.runningAppName != nil {
            moments.append(reading.takenAt.addingTimeInterval(RobotSnapshotStore.freshness))
        }
        return moments.filter { $0 > now }.sorted()
    }

    private func entry(at date: Date, apps: [RobotAppEntity]?, limit: Int) -> ReachyAppsEntry {
        ReachyAppsEntry(
            date: date,
            content: RobotAppsWidgetContent(
                configured: (apps ?? []).map(\.summary),
                cache: RobotAppsCacheStore().current,
                snapshot: RobotSnapshotStore().state(at: date),
                launch: RobotAppLaunchStateStore().current,
                hasKnownRobot: KnownRobots.lastAddress != nil,
                limit: limit,
                at: date
            )
        )
    }
}

struct ReachyAppsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: ReachyWidgetKind.apps,
            intent: RobotAppsConfigurationIntent.self,
            provider: ReachyAppsProvider()
        ) { entry in
            RobotAppsWidgetView(content: entry.content)
                .containerBackground(.fill.tertiary, for: .widget)
                // Every pixel a tile's `Button` does not claim. On iOS 18 this is
                // the *only* way a widget opens the app — an intent running in an
                // extension cannot — so it is what every "tap to open" refers to.
                .widgetURL(ReachyDeepLink.apps.url)
        }
        .configurationDisplayName("Reachy Apps")
        .description("Start your robot's apps from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
