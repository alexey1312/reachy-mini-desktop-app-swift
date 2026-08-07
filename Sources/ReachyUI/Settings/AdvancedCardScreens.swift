import ReachyDesign
import ReachyKit
import SwiftUI

/// Wrappers that give `WiFiSettingsCard` and `MaintenanceCard` a screen of their own.
///
/// Both cards are `Section`s, and a `Section` cannot be nested inside the
/// `DisclosureGroup` the Advanced group is built from. Rather than reshape two
/// working cards — whose contents are already covered by standalone references —
/// each gets a `Form` to sit in and a title of its own.
struct WiFiSettingsScreen: View {
    let session: RobotSession

    var body: some View {
        Form {
            WiFiSettingsCard(session: session)
        }
        .formStyle(.grouped)
        .navigationTitle(.reachy("Network"))
    }
}

struct MaintenanceScreen: View {
    let session: RobotSession

    var body: some View {
        Form {
            MaintenanceCard(session: session)
        }
        .formStyle(.grouped)
        .navigationTitle(.reachy("Maintenance"))
    }
}
