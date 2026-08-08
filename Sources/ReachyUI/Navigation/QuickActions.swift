import Foundation
import Observation
import ReachyDesign
import ReachyKit
#if os(iOS)
    import UIKit
#endif

/// A command reachable by touching and holding the app icon on the Home Screen.
///
/// **Not an `AppShortcut`, and the one cannot be built out of the other.** The two
/// look alike in a screenshot and are separate systems: App Shortcuts
/// (`ReachyShortcuts`, `AppShortcutsProvider`) surface in Spotlight, Siri and the
/// Shortcuts app and run in the background; the icon's menu is UIKit's
/// `UIApplicationShortcutItem`, holds four items at most, is iOS-only, and
/// **always launches the app**. So `WakeRobotIntent` and its neighbours do not
/// appear there however many of them are declared, and nothing here runs without a
/// window.
///
/// The items are installed at runtime rather than declared in `Info.plist` so
/// their titles come from the app's one catalogue (project rule 9) — a static
/// item's title is localized through `InfoPlist.strings`, which this app does not
/// have. The cost is that the menu is empty until the app has been launched once,
/// which is the same moment the robot becomes reachable at all.
public enum ReachyQuickAction: String, CaseIterable, Sendable {
    case wake
    case sleep
    case powerOff = "power-off"

    @MainActor
    func perform(on session: RobotSession) async {
        switch self {
        case .wake: await session.wake()
        case .sleep: await session.sleep()
        case .powerOff: await session.powerOff()
        }
    }

    /// The same words and glyphs as `RobotScreen.controlSection`, deliberately not
    /// the Control Centre buttons' (`figure.wave`, `moon.zzz.fill`): a menu is read
    /// against the screen it stands in for.
    private var title: LocalizedStringResource {
        switch self {
        case .wake: .reachy("Wake up")
        case .sleep: .reachy("Go to sleep")
        case .powerOff: .reachy("Power off")
        }
    }

    private var systemImage: String {
        switch self {
        case .wake: "sun.max"
        case .sleep: "moon.zzz"
        case .powerOff: "power"
        }
    }

    /// Writes the menu. A no-op everywhere but iOS, where there is no such menu.
    @MainActor
    public static func install() {
        #if os(iOS)
            UIApplication.shared.shortcutItems = allCases.map(\.shortcutItem)
        #endif
    }

    #if os(iOS)
        private var shortcutItem: UIApplicationShortcutItem {
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: String(localized: title),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: systemImage)
            )
        }
    #endif
}

/// Where a tapped quick action waits for the interface to notice it.
///
/// UIKit builds the scene delegate that receives the tap, so there is no
/// initialiser to inject anything through and `shared` is what the delegate can
/// reach. The type is ordinary all the same — tests build their own.
@MainActor
@Observable
public final class QuickActionInbox {
    /// The token is what makes two identical taps two events. Without it the second
    /// "Wake up" in a row writes the value that is already there and `onChange`
    /// never fires.
    public struct Pending: Equatable, Sendable {
        public let action: ReachyQuickAction
        let token: Int
    }

    public static let shared = QuickActionInbox()

    public private(set) var pending: Pending?
    private var issued = 0

    public init() {}

    /// `false` for an identifier this app does not own, which is also the answer
    /// UIKit wants back from `performActionFor`.
    @discardableResult
    public func receive(type: String) -> Bool {
        guard let action = ReachyQuickAction(rawValue: type) else { return false }
        issued += 1
        pending = Pending(action: action, token: issued)
        return true
    }

    /// Reading it is taking it: a command must run once, and the tab change behind
    /// it is not worth repeating on the next unrelated update.
    func take() -> ReachyQuickAction? {
        defer { pending = nil }
        return pending?.action
    }
}
