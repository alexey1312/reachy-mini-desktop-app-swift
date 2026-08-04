import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Stepper — handshaking") {
    PreviewScene.stepper(.handshaking)
}

#Preview("Stepper — checking backend") {
    PreviewScene.stepper(.checkingBackend(.preview))
}

#Preview("Stepper — backend unavailable") {
    PreviewScene.stepper(.backendUnavailable(.preview, daemonMessage: "Backend not running"))
}

#Preview("Stepper — backend unavailable, no message") {
    PreviewScene.stepper(.backendUnavailable(.preview, daemonMessage: nil))
}

#Preview("Stepper — connect failed") {
    PreviewScene.stepper(.failed(.connect, message: "Could not connect to the server."))
}

#Preview("Stepper — backend failed") {
    PreviewScene.stepper(.failed(.backend, message: "The backend never became ready."))
}

// A power transition replaces the decision buttons with live status, so the user cannot start a
// second backend while the first is still coming up.
#Preview("Stepper — starting backend") {
    PreviewScene.stepper(.backendUnavailable(.preview, daemonMessage: nil), powerTransition: .startingBackend)
}
