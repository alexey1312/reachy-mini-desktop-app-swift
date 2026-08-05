import AppIntents
import ReachyWidgetUI

/// Pulls `ReachyWidgetUI`'s intents and entities into this extension's metadata,
/// which is what the widget's configuration UI is built from.
struct WidgetIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [ReachyWidgetIntentsPackage.self]
    }
}
