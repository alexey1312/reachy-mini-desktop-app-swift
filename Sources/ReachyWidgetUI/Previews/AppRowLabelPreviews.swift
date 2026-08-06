import ReachyDesign
import ReachyKit
import ReachyWidgetUI
import SwiftUI

// The row two surfaces draw, at each of its layouts. The dock and the widget both
// capture it in place already; what these add is the shape on its own, at a width
// close to the real one, where the difference between the two presets — spacing,
// title size, and whether anything is kept clear after the row — is the only thing
// on screen.
//
// The badge is not repeated here: `Apps — one crashed` covers it on the artwork it
// belongs to.

#Preview("App row — dock layout", traits: .sizeThatFitsLayout) {
    AppRowLabel(
        artwork: AppArtwork(AppsPreview.dance),
        title: AppsPreview.dance.title,
        layout: .dock,
        status: ReachyStatusLabel(text: "Running", tone: .idle, lineLimit: 2)
    )
    .frame(width: 260)
    .padding()
}

#Preview("App row — tile layout", traits: .sizeThatFitsLayout) {
    AppRowLabel(
        artwork: AppArtwork(AppsPreview.chess),
        title: AppsPreview.chess.title,
        layout: .tile,
        titleWeight: .regular,
        status: ReachyStatusLabel(
            text: "Not installed",
            tone: .idle,
            font: Typography.statusCompact,
            lineLimit: 1
        )
    )
    .frame(width: 150)
    .padding()
}
