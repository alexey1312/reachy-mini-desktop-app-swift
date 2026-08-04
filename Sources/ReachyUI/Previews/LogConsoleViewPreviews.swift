@testable import ReachyUI
import SwiftUI

// The console body has three callers, and `LogConsoleScreen` is the only one a snapshot reaches
// through its own screen — the other two open it in a sheet, which never appears in the parent's
// capture. These cover the sources those sheets show.

#Preview("Console — installer log") {
    PreviewScene.consoleView(
        .preview(lines: PreviewScene.installerLines),
        source: "192.168.1.42",
        emptyDescription: "The robot has not sent any installer output yet."
    )
}

#Preview("Console — installer log, nothing yet") {
    PreviewScene.consoleView(
        .preview(lines: []),
        emptyDescription: "The robot has not sent any installer output yet."
    )
}

// Named by hardware id rather than address: over Bluetooth the robot has no address to show.
#Preview("Console — Bluetooth journal") {
    PreviewScene.consoleView(
        .preview(lines: PreviewScene.journalLines),
        source: "a1b2c3d4e5f60718",
        emptyDescription: "The robot only logs when something happens."
    )
}
