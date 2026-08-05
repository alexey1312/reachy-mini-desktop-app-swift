import AppIntents
import ReachyWidgetUI

/// Siri phrases for the intents themselves, which live in `ReachyWidgetUI` so the
/// widget extension can reach them too.
///
/// This provider stays in the app: Apple resolves shortcuts from the main bundle,
/// and one declared in an extension is not offered.
struct ReachyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WakeRobotIntent(),
            phrases: ["Wake up \(.applicationName)"],
            shortTitle: "Wake up",
            systemImageName: "figure.wave"
        )
        AppShortcut(
            intent: SleepRobotIntent(),
            phrases: ["Put \(.applicationName) to sleep"],
            shortTitle: "Sleep",
            systemImageName: "moon.zzz.fill"
        )
    }
}
