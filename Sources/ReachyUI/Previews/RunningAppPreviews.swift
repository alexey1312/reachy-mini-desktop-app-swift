import ReachyKit
@testable import ReachyUI
import SwiftUI

// MARK: - The dock

// Components, so `.sizeThatFitsLayout` rather than a device trait: the strip is
// what these capture, not the screen it is pinned under.

#Preview("Dock — running", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.preview(.running))
}

#Preview("Dock — conversation listening", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.previewConversation, conversationTurn: .listening)
}

#Preview("Dock — conversation thinking", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.previewConversation, conversationTurn: .thinking)
}

#Preview("Dock — conversation speaking", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.previewConversation, conversationTurn: .speaking)
}

#Preview("Dock — conversation ready", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.previewConversation, conversationTurn: .ready)
}

#Preview("Dock — starting", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.preview(.starting))
}

#Preview("Dock — stopping", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.preview(.stopping), busy: true)
}

// A crashed app offers Dismiss instead of Stop — there is nothing left to stop,
// and the strip would otherwise sit there for good.
#Preview("Dock — crashed", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.previewCrashed)
}

// The robot went quiet. The app is probably still running, so the strip stays —
// but its controls cannot reach it and are shown inert rather than lying.
#Preview("Dock — unreachable", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.preview(.running), isReachable: false)
}

// A daemon newer than this client. Its own word for the state is carried through
// rather than replaced with "Unknown" (project rule 3).
#Preview("Dock — unfamiliar state", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.preview(.unknown("reloading")))
}

// MARK: - Merged into a minimised tab bar

// The two captures of `.inline`, and the only cover it can have: reaching it for
// real takes a finger scrolling a list down, and nothing scrolls in a snapshot.
// What they certify is the row's *contents* — no caption, one control — not the
// width the system ends up giving it.
//
// Every capture above is `.standalone`, which is the shape below iOS 26.1 and on
// macOS: the strip backing itself.
#Preview("Dock — inline", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.preview(.running), placement: .inline)
}

#Preview("Dock — inline, crashed", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.previewCrashed, placement: .inline)
}

// MARK: - In the system's own container

// `.expanded` is the shape every iOS 26.1 device gets, and **no root capture shows
// it**: `PreviewScene.root` forces `.legacy` on all of them, so each renders the
// fallback's `.standalone` instead. This is the placement's only cover.
//
// What it certifies is an absence. The system's slot draws the capsule, so the
// strip must draw none — and the row is otherwise identical to `Dock — running`,
// which is exactly what makes the reference worth having: put a background back
// and these two images become the same one.
//
// It captures at all because the thing that blanks a capture is the system's glass
// container, not the placement value, and a component preview mounts no container.
#Preview("Dock — expanded", traits: .sizeThatFitsLayout) {
    PreviewScene.runningAppDock(.preview(.running), placement: .expanded)
}

// MARK: - The expanded page

// The dock expands into `AppDetailSheet` — the same page a store row opens — so
// these capture that page in the states only a running app reaches. The pair to
// keep is `running` and `conversation`: the first declares no port and shows no
// Settings row, the second declares 7860 and shows one. A reference for the
// offered state alone cannot tell a conditional row from a permanent one.

#Preview("Running app — running") {
    PreviewScene.runningAppDetail(.preview(.running))
}

#Preview("Running app — conversation") {
    PreviewScene.runningAppDetail(.previewConversation, conversationTurn: .listening)
}

#Preview("Running app — crashed") {
    PreviewScene.runningAppDetail(.previewCrashed)
}

#Preview("Running app — unreachable") {
    PreviewScene.runningAppDetail(.preview(.running), phase: .unreachable(.preview))
}

// The stop call itself failed — distinct from the app failing, and the only place
// that reason is shown.
#Preview("Running app — command failed") {
    PreviewScene.runningAppDetail(
        .preview(.running),
        model: .preview(error: "The daemon rejected the request (HTTP 400)")
    )
}
