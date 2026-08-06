import ReachyKit
import ReachyMedia
import ReachyScene
@testable import ReachyUI
import SwiftUI

// What these references do and do not prove, before anything is read into them:
//
// - **The 3D window fixes its frame, its corner and its chrome, never its content.**
//   `RealityView` renders nothing headless, so the pane behind the icons is the
//   scene's own progress overlay and not the robot.
// - **The tab at the edge takes the `.window` role, which carries no glass.** That
//   is what makes its dark reference worth having: `.chrome` renders as opaque
//   light glass in both appearances, so a dark capture of one says nothing about
//   how it looks on a device. `ReachyDesign/AGENTS.md` carries the measurement.
// - The window's own switcher *is* `.chrome`, so read its dark capture for layout
//   and never for colour.

#Preview("Floating viewport — 3D", traits: .sizeThatFitsLayout) {
    PreviewScene.floatingViewport(
        .preview(),
        viewport: .preview(sceneModel: .preview(.buildingScene))
    )
}

// The relay's only content, and the one the switcher starts on there.
#Preview("Floating viewport — camera", traits: .sizeThatFitsLayout) {
    PreviewScene.floatingViewport(
        .preview(.floating(.topLeading)),
        viewport: .preview(content: .camera, cameraSession: .preview(.waitingForProducer))
    )
}

// A wired robot reports no camera, so the window shows the 3D pane with no switcher
// on it at all — the same rule the Live tab's picker follows.
#Preview("Floating viewport — no camera", traits: .sizeThatFitsLayout) {
    PreviewScene.floatingViewport(
        .preview(.floating(.bottomLeading)),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        session: .preview(status: .preview(wirelessVersion: false))
    )
}

// The window stays where it is when the robot stops answering and says so in the
// corner — going away would lose the place the user put it over a blip.
#Preview("Floating viewport — reconnecting", traits: .sizeThatFitsLayout) {
    PreviewScene.floatingViewport(
        .preview(.floating(.topTrailing)),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        session: .preview(phase: .unreachable(.preview))
    )
}

// Switched off. The tab keeps the mode's icon and a dot for the link, so what comes
// back is predictable before it does.
#Preview("Floating viewport — tab at the leading edge", traits: .sizeThatFitsLayout) {
    PreviewScene.floatingViewport(.preview(.docked(.leading, y: 200)))
}

#Preview("Floating viewport — tab at the trailing edge", traits: .sizeThatFitsLayout) {
    PreviewScene.floatingViewport(
        .preview(.docked(.trailing, y: 320)),
        viewport: .preview(content: .camera, cameraSession: .preview(.waitingForProducer))
    )
}

// And with the robot unreachable, which is the only thing the tab can report while
// the stream is off.
#Preview("Floating viewport — tab, unreachable", traits: .sizeThatFitsLayout) {
    PreviewScene.floatingViewport(
        .preview(.docked(.trailing, y: 320)),
        session: .preview(phase: .unreachable(.preview))
    )
}

// In place, which is the only way to see what no component capture can: that the
// window clears the floating tab bar and lands inside the safe area. iPhone only —
// on iPad the shell draws a sidebar and the viewport never leaves the Live tab, so
// the iPad half of each of these is the plain tab it is captured on.
//
// The plain floating case needs nothing new: `Root — connected` builds the model
// with its own defaults and is now that capture. These two are the states a default
// cannot reach.
//
// The first answers "does it sit on the dock's buttons": both are in the bottom
// inset, and the window is the one that has to give way.
#Preview("Root — floating viewport over the dock") {
    PreviewScene.root(
        .preview(runningApp: .preview(.running)),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        floating: .preview(),
        tab: .apps
    )
}

// Captured on the Robot tab and not on Moves, which was the obvious choice: a tab
// whose content arrives through a `.task` loses the race against the shell building
// all five at once, and comes out half drawn. `AGENTS.md` records which tabs have a
// usable root capture — the placement is the point here, so it is taken on one that
// settles.
#Preview("Root — viewport docked at the edge") {
    PreviewScene.root(
        .preview(),
        viewport: .preview(sceneModel: .preview(.buildingScene)),
        floating: .preview(.docked(.trailing, y: 420))
    )
}
