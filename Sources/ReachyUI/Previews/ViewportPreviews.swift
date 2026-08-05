import ReachyMedia
import ReachyScene
@testable import ReachyUI
import SwiftUI

#Preview("Viewport — connecting to the scene") {
    PreviewScene.viewport(.preview())
}

#Preview("Viewport — connecting to the camera") {
    PreviewScene.viewport(.preview(content: .camera))
}

#Preview("Viewport — unavailable") {
    PreviewScene.viewport(.preview(setupError: "Could not reach 192.168.1.42"))
}

// A wired robot reports no camera, so there is nothing to switch between and the picker goes away
// rather than sitting there disabled.
#Preview("Viewport — no camera") {
    PreviewScene.viewport(.preview(), offersCamera: false)
}

#Preview("Viewport — scene building") {
    PreviewScene.viewport(.preview(sceneModel: .preview(.buildingScene)))
}

#Preview("Viewport — camera waiting") {
    PreviewScene.viewport(.preview(content: .camera, cameraSession: .preview(.waitingForProducer)))
}

// Over the relay the URDF and its meshes are out of reach, so the 3D pane says so once instead of
// spinning on a download that is never going to start.
#Preview("Viewport — no 3D over the relay") {
    PreviewScene.viewport(.preview(source: .remote(.preview(.waitingForProducer))))
}

// And with only the camera to show, the switcher is gone rather than offering a dead segment.
#Preview("Viewport — remote camera") {
    let camera = CameraSession.preview(.waitingForProducer)
    return PreviewScene.viewport(
        .preview(content: .camera, cameraSession: camera, source: .remote(camera))
    )
}
