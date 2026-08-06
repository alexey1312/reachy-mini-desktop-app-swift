import ReachyKit
import ReachyMedia
import ReachyScene
@testable import ReachyUI
import SwiftUI

// The root is a gate or a five-tab shell and nothing else, so every capture here is one of those two.
// The iPad shots are the ones carrying `.sidebarAdaptable`: the same five tabs, as a sidebar.

#Preview("Root — idle") {
    PreviewScene.root(.preview(phase: .idle, status: nil, address: nil))
}

#Preview("Root — connecting") {
    PreviewScene.root(.preview(phase: .connecting(.handshaking), status: nil, address: nil))
}

// The gate's other branch: start / continue / cancel, with the discovery list suppressed. The
// orienting line goes with it — a decision the user has to make is not something to talk over — and
// the readable width still holds, which is what this capture is for on iPad.
#Preview("Root — gate needs a decision") {
    PreviewScene.root(
        .preview(
            phase: .connecting(.backendUnavailable(.preview, daemonMessage: "Backend not running")),
            status: nil,
            address: nil
        )
    )
}

#Preview("Root — connected") {
    PreviewScene.root(.preview(), viewport: .preview(sceneModel: .preview(.buildingScene)))
}

// `.unreachable` keeps the shell rather than dropping back to the gate: a network blip must not pull
// the tab bar out from under a finger. This is the capture that proves it.
#Preview("Root — unreachable") {
    PreviewScene.root(
        .preview(phase: .unreachable(.preview)),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}

// Without a running backend there is no geometry and no state stream, so the Live tab says so rather
// than showing an empty viewport.
#Preview("Root — no live view") {
    PreviewScene.root(
        .preview(status: .preview(state: .stopped)),
        viewport: .preview(address: nil),
        tab: .live
    )
}

#Preview("Root — live tab") {
    PreviewScene.root(
        .preview(),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        tab: .live
    )
}

// The one state that renders the asleep banner in place, pinned to the top of the tab.
#Preview("Root — live tab asleep") {
    PreviewScene.root(
        .preview(status: .preview(motorMode: .disabled)),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        tab: .live
    )
}

// Neither Moves-over-the-network nor Settings has a root capture, and both for the same reason —
// see `AGENTS.md`. `MovesScreenPreviews` and `SettingsPreviews` cover those screens; that they sit at
// the root of a tab is what `Root — relay moves tab` below shows, from a state that needs no `.task`.

// The dock, in place. These are the captures that verify it lands *below* the tab bar and shrinks the
// interface rather than floating over it — which no unit test can see. Under `.sidebarAdaptable` the
// iPad shot is the interesting one: the bar is a sidebar on the left, so the strip is not under it but
// under the whole window, running the full width. The Telegram shape survives the move.
#Preview("Root — dock on the robot tab") {
    PreviewScene.root(
        .preview(runningApp: .preview(.running)),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}

// The reason the dock was hoisted out of the Apps tab: it is the same strip here, and the store below
// it no longer carries a second copy of the same control.
#Preview("Root — dock on the apps tab") {
    PreviewScene.root(.preview(runningApp: .preview(.running)), tab: .apps)
}

// A crashed app keeps the strip until it has been read, and offers Dismiss rather than Stop.
#Preview("Root — dock, crashed app") {
    PreviewScene.root(
        .preview(runningApp: .previewCrashed),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}

// A wired robot reports no camera, so the viewport offers no switcher and shows the 3D model alone.
// Captured on the Live tab: that is the only place the flag changes anything, and on the robot tab
// this preview was byte-identical to `Root — connected` and verified nothing.
#Preview("Root — no camera") {
    PreviewScene.root(
        .preview(status: .preview(wirelessVersion: false)),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        tab: .live
    )
}

// The relay session, which the root used to treat as no session at all.
#Preview("Root — over the relay") {
    let link = RemoteRobotLink.preview()
    return PreviewScene.root(
        .preview(address: nil, link: .remote, client: PreviewRemoteRobotClient()),
        viewport: .preview(content: .camera, cameraSession: link.camera, source: .remote(link.camera)),
        hfAccount: PreviewScene.account(in: .signedIn(username: "alexey1312")),
        remoteLink: link
    )
}

// The Live tab over the relay shows the camera the link already holds, rather than one it would dial.
#Preview("Root — relay live tab") {
    let link = RemoteRobotLink.preview()
    return PreviewScene.root(
        .preview(address: nil, link: .remote, client: PreviewRemoteRobotClient()),
        viewport: .preview(content: .camera, cameraSession: link.camera, source: .remote(link.camera)),
        tab: .live,
        hfAccount: PreviewScene.account(in: .signedIn(username: "alexey1312")),
        remoteLink: link
    )
}

// The move library is HTTP-only, so the relay reaches none of it. The tab stays and says why, which is
// what an unconditional tab buys over one that disappears.
#Preview("Root — relay moves tab") {
    PreviewScene.root(
        .preview(address: nil, link: .remote, client: PreviewRemoteRobotClient()),
        tab: .moves,
        hfAccount: PreviewScene.account(in: .signedIn(username: "alexey1312"))
    )
}

// The store is not merely unreached over the relay — the data channel carries no app command at all —
// so the screen names that instead of claiming no robot is connected.
#Preview("Root — apps need the local network") {
    PreviewScene.root(
        .preview(address: nil, link: .remote, client: PreviewRemoteRobotClient()),
        tab: .apps,
        hfAccount: PreviewScene.account(in: .signedIn(username: "alexey1312"))
    )
}

// Where signing in matters most: no robot yet, so the gate has the whole screen, and the remote list
// below stays empty until it happens.
#Preview("Root — idle, signed in") {
    PreviewScene.root(
        .preview(phase: .idle, status: nil, address: nil),
        hfAccount: PreviewScene.account(in: .signedIn(username: "alexey1312"))
    )
}

// The session lapsed and cannot be renewed silently — worth seeing before the next thing that needs
// it fails.
#Preview("Root — session expired") {
    PreviewScene.root(
        .preview(phase: .idle, status: nil, address: nil),
        hfAccount: PreviewScene.account(in: .needsReauth(username: "alexey1312"))
    )
}
