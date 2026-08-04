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

// A wired robot reports no camera; the viewport still shows the 3D model.
#Preview("Root — no camera") {
    PreviewScene.root(
        .preview(status: .preview(wirelessVersion: false)),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}
