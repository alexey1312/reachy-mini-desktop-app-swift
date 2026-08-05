import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Your Reachies — signed out") {
    PreviewScene.yourReachies(.signedOut)
}

// Carries an indeterminate ProgressView, so its reference — and, per the note in
// AGENTS.md, a handful of unrelated ones — moves with where in the run it lands.
#Preview("Your Reachies — asking") {
    PreviewScene.yourReachies(.loading)
}

// The state the screen is in most often for a user whose robot is simply off:
// central sweeps a lapsed peer, so an absent robot is the whole signal.
#Preview("Your Reachies — none online") {
    PreviewScene.yourReachies(.empty)
}

#Preview("Your Reachies — one online") {
    PreviewScene.yourReachies(.listed([.preview(name: "Reachy Mini")]))
}

#Preview("Your Reachies — several") {
    PreviewScene.yourReachies(.listed([
        .preview(peerID: "p1", name: "Kitchen", hardwareID: "a1b2c3d4e5f60718"),
        .preview(peerID: "p2", name: "Workshop", hardwareID: "b2c3d4e5f6071829", transport: "usb"),
        .preview(
            peerID: "p3",
            name: "Demo unit",
            hardwareID: "c3d4e5f607182930",
            isBusy: true,
            activeApp: "Hand Tracker"
        ),
    ]))
}

// Not a retry: the same token would be refused again, so the only useful button
// is a fresh sign-in.
#Preview("Your Reachies — session expired") {
    PreviewScene.yourReachies(.needsSignIn)
}

#Preview("Your Reachies — central unreachable") {
    PreviewScene.yourReachies(.failed("Too many requests. Wait a moment before refreshing again."))
}

// The robots did not go away — the request did — so the list stays and the
// failure sits above it.
#Preview("Your Reachies — refresh failed over a list") {
    PreviewScene.yourReachies(
        .listed([.preview(name: "Kitchen")]),
        refreshFailure: "Hugging Face answered 503."
    )
}
