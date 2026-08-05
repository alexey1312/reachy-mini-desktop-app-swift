import ReachyKit
import ReachyMedia
import ReachyScene
@testable import ReachyUI
import SwiftUI

// The iPad captures of these are the point of the whole suite: the root view branches on
// `horizontalSizeClass`, and the two-column layout had never been verified on anything.

#Preview("Root — idle") {
    PreviewScene.root(.preview(phase: .idle, status: nil, address: nil))
}

#Preview("Root — connecting") {
    PreviewScene.root(.preview(phase: .connecting(.handshaking), status: nil, address: nil))
}

#Preview("Root — connected") {
    PreviewScene.root(.preview(), viewport: .preview(sceneModel: .preview(.buildingScene)))
}

#Preview("Root — unreachable") {
    PreviewScene.root(
        .preview(phase: .unreachable(.preview)),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}

// Without a running backend there is no geometry and no state stream, so the wide layout says so
// rather than showing an empty viewport.
#Preview("Root — no live view") {
    PreviewScene.root(.preview(status: .preview(state: .stopped)), viewport: .preview(address: nil))
}

// The Live tab exists only on a compact width behind a running backend, so nothing captured it
// until the tab could be selected outright — which is why a title pinned against its backdrop
// went unverified. The iPad capture of this is the regular-width layout, where the tab is absent.
#Preview("Root — live tab") {
    PreviewScene.root(
        .preview(),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        tab: .live
    )
}

// The one state that renders `asleepViewport`, and the only capture of it in place: the iPhone
// shot is the Live tab, the iPad one the wide column, which is the same view in a narrower space.
#Preview("Root — live tab asleep") {
    PreviewScene.root(
        .preview(status: .preview(motorMode: .disabled)),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        tab: .live
    )
}

// The dock, in place. These are the captures that verify it lands *below* the tab bar and shrinks
// the interface rather than floating over it — which no unit test can see, and which differs
// between the two size classes: the iPhone shot has the bar above the strip, the iPad one has it
// at the top of the window with the strip alone at the bottom.
#Preview("Root — dock on the robot tab") {
    PreviewScene.root(
        .preview(runningApp: .preview(.running)),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}

// The reason the dock was hoisted out of the Apps tab: it is the same strip here, and the store
// below it no longer carries a second copy of the same control.
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

// A wired robot reports no camera; the viewport still shows the 3D model.
#Preview("Root — no camera") {
    PreviewScene.root(
        .preview(status: .preview(wirelessVersion: false)),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}

// The relay session, which the root used to treat as no session at all. The wide layout shows the
// camera it was handed instead of "No live view", and the account sits in the leading slot.
#Preview("Root — over the relay") {
    let link = RemoteRobotLink.preview()
    return PreviewScene.root(
        .preview(address: nil, link: .remote, client: PreviewRemoteRobotClient()),
        viewport: .preview(content: .camera, cameraSession: link.camera, source: .remote(link.camera)),
        hfAccount: PreviewScene.account(in: .signedIn(username: "alexey1312")),
        remoteLink: link
    )
}

// The iPhone capture is the one that matters here: the Live tab exists over the relay at all,
// which is the fix. Its iPad twin is the regular-width layout, where the tab is absent.
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

// The store is not merely unreached over the relay — the data channel carries no app command at
// all — so the screen names that instead of claiming no robot is connected.
#Preview("Root — apps need the local network") {
    PreviewScene.root(
        .preview(address: nil, link: .remote, client: PreviewRemoteRobotClient()),
        tab: .apps,
        hfAccount: PreviewScene.account(in: .signedIn(username: "alexey1312"))
    )
}

// Where signing in matters most: no robot yet, so no Settings to reach it through, and the remote
// list below stays empty until it happens.
#Preview("Root — idle, signed in") {
    PreviewScene.root(
        .preview(phase: .idle, status: nil, address: nil),
        hfAccount: PreviewScene.account(in: .signedIn(username: "alexey1312"))
    )
}

// The session lapsed and cannot be renewed silently — worth seeing before the next thing that
// needs it fails.
#Preview("Root — session expired") {
    PreviewScene.root(
        .preview(phase: .idle, status: nil, address: nil),
        hfAccount: PreviewScene.account(in: .needsReauth(username: "alexey1312"))
    )
}
