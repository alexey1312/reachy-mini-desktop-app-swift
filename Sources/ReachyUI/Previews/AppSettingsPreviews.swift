@testable import ReachyUI
import SwiftUI

// The page itself is a `WKWebView`, which renders nothing headless and is not
// even mounted under `reachyPreviewMode` — so what these cover is everything
// around it: the navigation chrome, the loading state, and the failure a robot
// that stopped answering mid-load produces.
//
// `.ready` is deliberately absent. It is the one phase in which nothing but the
// unrenderable layer is on screen, which is the same reason `SceneViewport` has
// no reference for its own `.ready` — and unlike `CameraViewport.streaming`,
// this phase grows no chrome of its own to capture over it.

#Preview("App settings — loading") {
    PreviewScene.appSettings(.loading)
}

// The app was running when the row was tapped and had stopped by the time the
// page loaded — the single most likely way to land here, because the process
// serving the page is the one that crashes.
#Preview("App settings — failed") {
    PreviewScene.appSettings(.failed("Could not connect to the server."))
}
