import ReachyMedia
@testable import ReachyUI
import SwiftUI

// `.streaming` is deliberately absent: the video layer is a Metal-backed `RTCMTLVideoView` and
// captures as an empty rectangle. The three phases that draw an overlay are covered.

#Preview("Camera — connecting") {
    PreviewScene.pane {
        CameraViewport(session: .preview(.connecting))
    }
}

#Preview("Camera — waiting for producer") {
    PreviewScene.pane {
        CameraViewport(session: .preview(.waitingForProducer))
    }
}

#Preview("Camera — unavailable") {
    PreviewScene.pane {
        CameraViewport(session: .preview(.failed("The robot closed the signaling socket.")))
    }
}
