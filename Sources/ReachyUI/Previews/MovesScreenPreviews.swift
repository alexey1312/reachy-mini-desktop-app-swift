import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Moves — library loaded") {
    PreviewScene.movesScreen(.preview())
}

#Preview("Moves — dances loading") {
    PreviewScene.movesScreen(.preview(), model: .preview(moves: [], loading: true))
}

#Preview("Moves — emotions loading") {
    PreviewScene.movesScreen(.preview(), model: .preview(moves: [], selection: 1, loading: true))
}

#Preview("Moves — music loading") {
    PreviewScene.movesScreen(.preview(), model: .preview(moves: [], selection: 2, loading: true))
}

#Preview("Moves — empty library") {
    PreviewScene.movesScreen(.preview(), model: .preview(moves: []))
}

#Preview("Moves — emotions selected") {
    PreviewScene.movesScreen(.preview(), model: .preview(selection: 1))
}

#Preview("Moves — music selected") {
    PreviewScene.movesScreen(.preview(), model: .preview(selection: 2))
}

#Preview("Moves — playing") {
    PreviewScene.movesScreen(.preview(currentMove: .preview(move: "happy_dance")))
}

#Preview("Moves — stopping") {
    PreviewScene.movesScreen(.preview(currentMove: .preview(move: "happy_dance"), isStoppingMove: true))
}

// Browsing stays available while the robot sleeps; only playback is gated.
#Preview("Moves — asleep") {
    PreviewScene.movesScreen(.preview(status: .preview(motorMode: .disabled)))
}

#Preview("Moves — error") {
    PreviewScene.movesScreen(.preview(error: "The daemon refused the move: 503 Backend not running."))
}
