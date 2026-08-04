import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Audio — both devices") {
    PreviewScene.audioSection()
}

#Preview("Audio — loading") {
    PreviewScene.audioSection(.preview(speaker: nil, microphone: nil, isLoading: true))
}

// A robot with no microphone still reports a speaker; the missing slider is disabled rather than
// hidden, so the section does not change shape between robots.
#Preview("Audio — speaker only") {
    PreviewScene.audioSection(.preview(microphone: nil))
}

#Preview("Audio — busy") {
    PreviewScene.audioSection(.preview(isBusy: true))
}

#Preview("Audio — error") {
    PreviewScene.audioSection(.preview(errorMessage: "The daemon has no audio device."))
}

// The sheet titles itself, so the section drops its own header there.
#Preview("Audio — sheet variant") {
    PreviewScene.audioSection(.preview(), header: nil)
}
