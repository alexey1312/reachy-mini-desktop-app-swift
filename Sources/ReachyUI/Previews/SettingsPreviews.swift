import ReachyKit
@testable import ReachyUI
import SwiftUI

// MARK: - The screen

#Preview("Settings — wireless robot") {
    PreviewScene.settings(.preview())
}

// A Lite robot mounts neither `/wifi/*` nor `/update/*`, so both cards are gone.
#Preview("Settings — Lite robot") {
    PreviewScene.settings(.preview(status: .preview(wirelessVersion: false)))
}

// `/api/daemon/robot-name` postdates 1.9.0, so the field is greyed out and the footer
// says what would make it editable — rather than a save that can only 404.
#Preview("Settings — rename unavailable") {
    PreviewScene.settings(.preview(supportsRename: false))
}

// Audio needs the backend up; the rest of the screen does not.
#Preview("Settings — backend stopped") {
    PreviewScene.settings(.preview(status: .preview(state: .stopped)))
}

// MARK: - System update

#Preview("System update — idle") {
    PreviewScene.updateCard(.idle)
}

#Preview("System update — checking") {
    PreviewScene.updateCard(.checking)
}

#Preview("System update — up to date") {
    PreviewScene.updateCard(.upToDate(current: "1.9.1"))
}

// The robot's own connectivity, not the app's — saying "the check failed" would send the user
// looking in the wrong place.
#Preview("System update — robot offline") {
    PreviewScene.updateCard(.robotOffline(current: "1.9.0"))
}

#Preview("System update — available") {
    PreviewScene.updateCard(.available(current: "1.9.0", latest: "1.9.1"))
}

#Preview("System update — installing") {
    PreviewScene.updateCard(.installing, log: PreviewScene.installerLines)
}

// The log socket closing is what the daemon restarting looks like, so this is a success state.
#Preview("System update — restarting") {
    PreviewScene.updateCard(.restarting, log: PreviewScene.installerLines)
}

#Preview("System update — finished") {
    PreviewScene.updateCard(.finished(version: "1.9.1"), log: PreviewScene.installerLines)
}

#Preview("System update — failed") {
    PreviewScene.updateCard(.failed("The robot reported that the update failed."))
}

// MARK: - Wi-Fi

#Preview("Wi-Fi — on a network") {
    PreviewScene.wifiCard(status: .preview)
}

#Preview("Wi-Fi — own hotspot") {
    PreviewScene.wifiCard(status: WiFiStatus(mode: .hotspot, connected: nil, known: ["Home"]))
}

// A failed join drops the robot back onto its hotspot and leaves the reason here, since the
// connect route answers before it has tried anything.
#Preview("Wi-Fi — join failed") {
    PreviewScene.wifiCard(
        status: WiFiStatus(mode: .hotspot, connected: nil, known: ["Home", "Cafe"]),
        joinError: "Secrets were required, but not provided."
    )
}

#Preview("Wi-Fi — status unavailable") {
    PreviewScene.wifiCard(loadFailure: "The robot did not answer in time.")
}
