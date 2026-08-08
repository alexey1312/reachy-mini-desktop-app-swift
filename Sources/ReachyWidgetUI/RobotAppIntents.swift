import AppIntents
import ReachyKit

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
/// widget's own bookkeeping, not a picker anyone should be offered. What Shortcuts
/// gets instead is `StartRobotAppIntent` and its two neighbours, which take a
/// `RobotAppEntity` and share every line of the work through `RobotAppCommand`.
public struct RobotAppTileIntent: AppIntent {
    public static let title: LocalizedStringResource = "Tap a Reachy Mini app tile"
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
        try await RobotAppCommand(.toggle(name: appName), appID: appID).perform()
        return .result()
    }
}
