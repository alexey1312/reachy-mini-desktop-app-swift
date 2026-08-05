import HuggingFaceAuth
import ReachyKit
@testable import ReachyUI
import SwiftUI

// The account moved out of Settings and into the leading slot of every tab's bar, because it
// outlives any one robot and is needed before one — signing in is what makes the remote robot
// list exist at all.
//
// Snapshots do capture toolbar items, so these verify the button itself; the storybook hoists
// navigation chrome out of its cards and will show them in its own bar instead.

#Preview("Account button — signed out") {
    PreviewScene.accountToolbar(.signedOut)
}

#Preview("Account button — signed in") {
    PreviewScene.accountToolbar(.signedIn(username: "alexey1312"))
}

// The session lapsed and cannot be renewed silently. The badge is the only warning before the
// next thing that needs a token fails.
#Preview("Account button — session expired") {
    PreviewScene.accountToolbar(.needsReauth(username: "alexey1312"))
}

#Preview("Account button — signing in") {
    PreviewScene.accountToolbar(.signingIn)
}
