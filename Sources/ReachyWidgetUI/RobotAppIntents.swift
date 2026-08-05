import AppIntents
import ReachyKit
import WidgetKit

/// One tile's tap: start the app, or stop it if it is the one running.
///
/// **Plain `String` parameters rather than a `RobotAppEntity`.** Three reasons,
/// and the third is the load-bearing one: a tile builds this without an entity or
/// a query in scope; `perform` only ever needed the name; and the tap therefore
/// does not depend on the system having extracted metadata for a type declared in
/// a Swift package. If that extraction ever fails it costs the widget its
/// configuration UI, not its buttons.
///
/// Hidden from Shortcuts (`isDiscoverable`) because those parameters are the
/// widget's own bookkeeping, not a picker anyone should be offered. Siri gets
/// wake and sleep.
public struct ToggleRobotAppIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start or stop a Reachy Mini app"
    public static let description = IntentDescription(
        "Starts an app on your robot, or stops it if it is already running."
    )
    public static let isDiscoverable = false
    // No `openAppWhenRun`: it is deprecated *and* errors when an intent runs in an
    // app extension, which is exactly where a widget button runs it. Its
    // replacement, `supportedModes`, is iOS 26 and this app deploys to 18. So the
    // offer to open the app lives in the view's `widgetURL`, not here — see
    // `RobotPowerIntents` for the same reasoning about Control Centre.

    @Parameter(title: "App") public var appID: String
    @Parameter(title: "Name") public var appName: String

    public init() {}

    public init(id: String, name: String) {
        appID = id
        appName = name
    }

    public func perform() async throws -> some IntentResult {
        let snapshots = RobotSnapshotStore()
        let launches = RobotAppLaunchStateStore()

        // Written *before* the request, and the reload right behind it: this is the
        // only way the tile can say "Starting…" while the call is still out. It
        // also survives the process being killed mid-call, which a piece of memory
        // would not — `pendingWindow` is what expires it instead.
        launches.begin(appID: appID, isStop: isStopping(named: appName, snapshots: snapshots))
        reload()

        do {
            // A reading inside its window is worth a round trip saved; past it,
            // ask. `RobotAppLauncher` treats nil as "find out".
            let assumeAwake: Bool? = if case let .fresh(reading) = snapshots.state() {
                reading.isAwake
            } else {
                nil
            }
            let launcher = try RobotAppLauncher(
                client: RobotIntentTarget.connection(timeout: 6),
                assumeAwake: assumeAwake
            )
            switch try await launcher.toggle(name: appName) {
            case let .started(name, title):
                snapshots.recordRunningApp(title: title, name: name, isAwake: true)
            case .stopped:
                snapshots.recordRunningApp(title: nil, name: nil, isAwake: true)
            }
            launches.succeed(appID: appID)
        } catch {
            launches.fail(appID: appID, message: RobotSession.describe(error))
            reload()
            // Rethrown *after* the reload, not instead of it. On iOS 18 what the
            // user sees is the widget's own notice; the thrown error is for
            // Shortcuts and for a debugger.
            throw error
        }

        reload()
        return .result()
    }

    /// Which caption the pending tile should carry. Wrong only when the reading is
    /// stale, and then the launcher corrects the outcome a second later.
    private func isStopping(named name: String, snapshots: RobotSnapshotStore) -> Bool {
        guard case let .fresh(reading) = snapshots.state() else { return false }
        return reading.runningAppName == name
    }

    /// Both widgets: a running app is also what `RobotWidgetContent` puts in front
    /// of the awake reading.
    private func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: ReachyWidgetKind.apps)
        WidgetCenter.shared.reloadTimelines(ofKind: ReachyWidgetKind.status)
    }
}
