import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Daemon update — available") {
    PreviewScene.daemonUpdate(
        DaemonUpdateRequirement(reported: "1.8.2", minimum: "1.9.0", canSelfUpdate: true),
        state: .available(current: "1.8.2", latest: "1.9.1")
    )
}

#Preview("Daemon update — checking") {
    PreviewScene.daemonUpdate(
        DaemonUpdateRequirement(reported: "1.8.2", minimum: "1.9.0", canSelfUpdate: true),
        state: .checking
    )
}

// The dead end: the robot is on the newest published release and it is still too old for this
// app. Nothing here can fix it, so the screen has to say so rather than offer a button.
#Preview("Daemon update — newest is still too old") {
    PreviewScene.daemonUpdate(
        DaemonUpdateRequirement(reported: "1.8.2", minimum: "1.9.0", canSelfUpdate: true),
        state: .upToDate(current: "1.8.2")
    )
}

#Preview("Daemon update — robot offline") {
    PreviewScene.daemonUpdate(
        DaemonUpdateRequirement(reported: "1.8.2", minimum: "1.9.0", canSelfUpdate: true),
        state: .robotOffline(current: "1.8.2")
    )
}

#Preview("Daemon update — finished") {
    PreviewScene.daemonUpdate(
        DaemonUpdateRequirement(reported: "1.8.2", minimum: "1.9.0", canSelfUpdate: true),
        state: .finished(version: "1.9.1")
    )
}

// A Lite robot has no `/update/*` at all — the whole update section is replaced by an
// explanation pointing at the desktop app over USB.
#Preview("Daemon update — cannot self-update") {
    PreviewScene.daemonUpdate(
        DaemonUpdateRequirement(reported: "1.8.2", minimum: "1.9.0", canSelfUpdate: false)
    )
}
