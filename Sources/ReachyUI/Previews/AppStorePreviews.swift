import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Apps — discover") {
    PreviewScene.appStore(.preview())
}

#Preview("Apps — installed") {
    PreviewScene.appStore(.preview(), model: .preview(section: .installed))
}

#Preview("Apps — update available") {
    PreviewScene.appStore(.preview(), model: .preview(section: .installed, hasUpdate: true))
}

#Preview("Apps — running") {
    PreviewScene.appStore(
        .preview(),
        model: .preview(
            section: .installed,
            running: RobotAppStatus(app: RobotApp.previewInstalled[0], state: .running),
            startupApp: "reachy_mini_dance"
        )
    )
}

// A relay session holds the same lock a local app does. The screen has to explain
// itself rather than just disable the buttons.
#Preview("Apps — held remotely") {
    PreviewScene.appStore(
        .preview(),
        model: .preview(lock: RobotAppLockStatus(state: .remoteSession, holderName: "alexey1312"))
    )
}

#Preview("Apps — loading") {
    PreviewScene.appStore(.preview(), model: .preview(catalogue: [], installed: [], loading: true))
}

#Preview("Apps — nothing installed") {
    PreviewScene.appStore(.preview(), model: .preview(section: .installed, catalogue: [], installed: []))
}

// The robot answered, but it could not reach Hugging Face — which is the robot's
// connectivity, not this app's.
#Preview("Apps — store unavailable") {
    PreviewScene.appStore(
        .preview(),
        model: .preview(
            catalogue: [],
            installed: [],
            error: "The daemon rejected the request (HTTP 503)"
        )
    )
}

// MARK: - Detail sheet

#Preview("App detail — not installed") {
    PreviewScene.appDetail(.preview(), app: RobotApp.previewCatalogue[0])
}

#Preview("App detail — installed") {
    PreviewScene.appDetail(
        .preview(),
        app: RobotApp.previewCatalogue[0],
        model: .preview(section: .installed, startupApp: "reachy_mini_dance", hasUpdate: true)
    )
}

// A private Space needs the *robot* linked to an account, not this device.
#Preview("App detail — private space") {
    PreviewScene.appDetail(.preview(), app: RobotApp.previewCatalogue[3])
}

#Preview("App detail — installing") {
    PreviewScene.appDetail(
        .preview(),
        app: RobotApp.previewCatalogue[0],
        install: .preview(
            state: .running(.install(RobotApp.previewCatalogue[0])),
            log: PreviewScene.installerLines
        )
    )
}

#Preview("App detail — install failed") {
    PreviewScene.appDetail(
        .preview(),
        app: RobotApp.previewCatalogue[0],
        install: .preview(
            state: .failed(
                .install(RobotApp.previewCatalogue[0]),
                "No matching distribution found for reachy-mini-dance"
            ),
            log: PreviewScene.installerLines
        )
    )
}

// Neither success nor failure: the job register died with the daemon, so the
// installed list is the only thing that knows how it ended.
#Preview("App detail — robot restarted") {
    PreviewScene.appDetail(
        .preview(),
        app: RobotApp.previewCatalogue[0],
        install: .preview(state: .daemonRestarted(.install(RobotApp.previewCatalogue[0])))
    )
}
