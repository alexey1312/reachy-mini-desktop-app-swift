import ReachyDesign
import ReachyKit
import SwiftUI

/// The account card as a destination of its own.
///
/// «Your Reachies» needs a way in that does not leave the sheet it is in: the
/// list is what the user came for, and a robot's own settings are not where
/// signing in belongs — least of all when the reason there is no list yet is
/// that no robot is connected.
///
/// `HFAccountSection` renders its robot half only when a robot is connected, so
/// the same section stands alone here without a second copy of the sign-in
/// controls existing anywhere.
struct HFSignInScreen: View {
    let session: RobotSession
    let model: HFSignInModel

    var body: some View {
        Form {
            HFAccountSection(session: session, model: model)
        }
        // Named for what the user came to do, not for the service: the section
        // inside already carries "Hugging Face" as its header, and a screen
        // repeating it says nothing twice.
        .navigationTitle(.reachy("Sign in"))
    }
}
