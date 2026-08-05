import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Robot — connected") {
    PreviewScene.robotScreen(.preview())
}

#Preview("Robot — unreachable") {
    PreviewScene.robotScreen(.preview(phase: .unreachable(.preview)))
}

#Preview("Robot — backend stopped") {
    PreviewScene.robotScreen(.preview(status: .preview(state: .stopped)))
}

#Preview("Robot — motors disabled") {
    PreviewScene.robotScreen(.preview(status: .preview(motorMode: .disabled)))
}

#Preview("Robot — backend fault") {
    PreviewScene.robotScreen(.preview(status: .preview(error: "Power supply not connected")))
}

#Preview("Robot — compatibility warning") {
    PreviewScene.robotScreen(.preview(compatibilityWarning: "Daemon 1.10.0 is newer than the tested baseline 1.9.0."))
}

#Preview("Robot — error") {
    PreviewScene.robotScreen(.preview(error: "Could not connect to the server."))
}

#Preview("Robot — waking up") {
    PreviewScene.robotScreen(.preview(powerTransition: .wakingUp))
}

#Preview("Robot — starting backend") {
    PreviewScene.robotScreen(.preview(powerTransition: .startingBackend))
}

// Every identity field is optional and the daemon may report none of them; the screen falls back
// to em dashes and drops the links whose transport it does not have.
#Preview("Robot — nothing reported") {
    PreviewScene.robotScreen(.preview(phase: .connected(RobotIdentity()), status: nil, address: nil))
}

// Over the relay the connection is named rather than addressed, and only the moves are gone: the
// recorded-move library is HTTP-only, while the joystick and the journal both ride the data
// channel. Before this, all three vanished together for want of an address.
#Preview("Robot — over the relay") {
    PreviewScene.robotScreen(.preview(
        address: nil,
        link: .remote,
        client: PreviewRemoteRobotClient()
    ))
}
