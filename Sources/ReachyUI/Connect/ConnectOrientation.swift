import ReachyDesign
import SwiftUI

/// One line under the gate's title saying what the screen is waiting for.
///
/// It renders as a `Section` so it can sit inside `ConnectionScreen`'s form
/// rather than above it: the other two branches of that screen — the daemon
/// update and the start/continue/cancel decision — are screens in their own right
/// and would only be talked over. A clear row background is what keeps it reading
/// as prose under the title instead of as the first row of a list.
///
/// It lives beside `ConnectGate` because it is the gate's copy, and because
/// `ConnectionScreen` is at SwiftLint's `type_body_length` ceiling: the candidate
/// sweep inside it wants a model of its own before anything else is added there.
struct ConnectOrientation: View {
    var body: some View {
        Section {
            Text(.reachy("Your Reachy Mini appears below once it is powered on and joined to this Wi-Fi network."))
                .font(Typography.detail)
                .foregroundStyle(Tone.quiet.style)
                .listRowBackground(Color.clear)
        }
    }
}
