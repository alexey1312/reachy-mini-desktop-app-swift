import ReachyKit
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

// A wired robot reports no camera; the viewport still shows the 3D model.
#Preview("Root — no camera") {
    PreviewScene.root(
        .preview(status: .preview(wirelessVersion: false)),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}
