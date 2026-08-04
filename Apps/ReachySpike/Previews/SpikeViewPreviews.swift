import ReachyKit
import SwiftUI

// `SpikeView` lives in the ReachySpike app target, which neither the snapshot bundle nor the
// storybook can import. Both compile its two source files directly instead — see the source globs
// in `Apps/Project.swift`.

@MainActor
enum SpikePreviewScene {
    static func spike(_ model: SpikeModel, discovery: RobotBrowser? = nil) -> some View {
        SpikeView(
            model: model,
            discovery: discovery ?? .preview(names: []),
            browsesLiveNetwork: false
        )
    }
}

#Preview("Spike — searching") {
    SpikePreviewScene.spike(.preview())
}

#Preview("Spike — robots found") {
    SpikePreviewScene.spike(.preview(), discovery: .preview())
}

#Preview("Spike — permission denied") {
    SpikePreviewScene.spike(.preview(), discovery: .preview(names: [], permissionDenied: true))
}

#Preview("Spike — handshake done") {
    SpikePreviewScene.spike(.preview(handshakeSummary: SpikeModel.previewHandshake))
}

#Preview("Spike — handshake failed") {
    SpikePreviewScene.spike(.preview(lastError: "Could not connect to the server."))
}

#Preview("Spike — streaming") {
    SpikePreviewScene.spike(.preview(
        handshakeSummary: SpikeModel.previewHandshake,
        isStreaming: true,
        frameCount: 1247,
        hertz: 9.8
    ))
}
