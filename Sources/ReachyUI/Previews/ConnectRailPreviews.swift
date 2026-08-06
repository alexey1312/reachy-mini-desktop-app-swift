import ReachyKit
@testable import ReachyUI
import SwiftUI

// The rail replaces the vertical `ConnectionStepper`, and these replace its previews
// one for one — plus the two ends of the walk the old `ConnectionStep`-shaped
// factory could not express.
//
// Every capture renders the *resting* node: `ConnectRailNode` treats preview mode
// and Reduce Motion as the same case, so what a reference records is exactly what a
// reader who asked for less movement sees. Nothing here depends on where in the run
// the test landed.

#Preview("Rail — nothing attempted", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.idle)
}

#Preview("Rail — handshaking", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.handshaking)
}

// The middle node is done here without ever having been active: the version check
// happens inside the handshake. The reference is what keeps that visible.
#Preview("Rail — checking backend", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.checkingBackend(.preview))
}

#Preview("Rail — backend unavailable", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.backendUnavailable(.preview, daemonMessage: "Backend not running"))
}

// No daemon message: the detail line falls back to the app's own sentence rather
// than collapsing, so the buttons below do not move between the two cases.
#Preview("Rail — backend unavailable, no message", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.backendUnavailable(.preview, daemonMessage: nil))
}

#Preview("Rail — connect failed", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.failed(.connect, message: "Could not connect to the server."))
}

#Preview("Rail — backend failed", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.failed(.backend, message: "The backend never became ready."))
}

// A power transition replaces the decision buttons with live status, so the user
// cannot start a second backend while the first is still coming up.
#Preview("Rail — starting backend", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.backendUnavailable(.preview, daemonMessage: nil), powerTransition: .startingBackend)
}

// The frame `ConnectProgressModel.holdsGate` exists to keep on screen. Without that
// hold the root replaces the gate in the same tick this is drawn, and no reference
// could be recorded of it at all.
#Preview("Rail — all stages done", traits: .sizeThatFitsLayout) {
    PreviewScene.rail(.connected(.preview))
}
