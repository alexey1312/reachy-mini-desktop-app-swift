import ReachyScene
@testable import ReachyUI
import SwiftUI

// `.ready` is deliberately absent: it renders a bare `RealityView`, which produces nothing
// meaningful in a headless snapshot. Every phase that draws an overlay is covered.

#Preview("Scene — reading the description") {
    PreviewScene.pane { SceneViewport(model: .preview(.fetchingDescription)) }
}

#Preview("Scene — downloading meshes") {
    PreviewScene.pane { SceneViewport(model: .preview(.downloadingMeshes(completed: 3, total: 47))) }
}

#Preview("Scene — almost downloaded") {
    PreviewScene.pane { SceneViewport(model: .preview(.downloadingMeshes(completed: 46, total: 47))) }
}

#Preview("Scene — building") {
    PreviewScene.pane { SceneViewport(model: .preview(.buildingScene)) }
}

#Preview("Scene — failed") {
    PreviewScene.pane { SceneViewport(model: .preview(.failed("The robot served no URDF."))) }
}
