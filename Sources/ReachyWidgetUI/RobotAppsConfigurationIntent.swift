import AppIntents
import WidgetKit

/// What "Edit Widget" offers: which of the robot's apps this widget shows.
public struct RobotAppsConfigurationIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Reachy Apps"
    public static let description = IntentDescription(
        "Choose which of your robot's apps to show."
    )

    /// One list rather than a slot per family. `size` only decides how many rows
    /// the picker offers on each family; what actually bounds the grid is the
    /// `prefix` the timeline provider applies, so an oversized configuration
    /// carried over from a larger widget truncates rather than overflows.
    @Parameter(title: "Apps", size: [.systemSmall: 2, .systemMedium: 4, .systemLarge: 8])
    public var apps: [RobotAppEntity]?

    public init() {}
}
