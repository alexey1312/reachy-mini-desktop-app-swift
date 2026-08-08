import AppIntents
import WidgetKit

/// What "Edit Widget" offers: which of the robot's apps this widget shows.
public struct RobotAppsConfigurationIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Reachy Apps"
    public static let description = IntentDescription(
        "Choose which of your robot's apps to show."
    )

    /// One list rather than a slot per family. `size` is a *requirement* on the
    /// selection, not a hint about how many rows the picker offers — and a bare
    /// integer literal is `IntentCollectionSize(exactly:)`, which is what broke
    /// this widget: `.systemSmall: 2` meant a robot with one installed app could
    /// never satisfy the configuration, so WidgetKit never left the placeholder.
    /// Ranges from zero, because a robot's app list is whatever it happens to be.
    ///
    /// Zero is a real state rather than a lower bound nobody reaches:
    /// `RobotAppsWidgetContent` reads an empty selection as "show the robot's own
    /// list", which is what makes the widget useful the moment it lands. What
    /// bounds the grid is the `prefix` the timeline provider applies, so a
    /// selection carried over from a larger widget truncates rather than overflows.
    @Parameter(
        title: "Apps",
        size: [
            .systemSmall: .init(min: 0, max: 2),
            .systemMedium: .init(min: 0, max: 4),
            .systemLarge: .init(min: 0, max: 8),
        ]
    )
    public var apps: [RobotAppEntity]?

    public init() {}
}
