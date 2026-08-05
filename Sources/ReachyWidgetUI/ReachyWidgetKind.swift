/// The `kind` strings WidgetKit files installed widgets under.
///
/// Named here rather than at each `WidgetConfiguration` because an intent running
/// in the extension has to reload a timeline by kind, and a widget already on
/// someone's Home Screen is orphaned the moment its kind changes — so these two
/// literals are load-bearing and must not be edited casually.
public enum ReachyWidgetKind {
    public static let status = "RobotStatus"
    public static let apps = "ReachyApps"
}
