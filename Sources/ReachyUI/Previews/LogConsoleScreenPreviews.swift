@testable import ReachyUI
import SwiftUI

#Preview("Log console — streaming") {
    PreviewScene.logConsole()
}

#Preview("Log console — waiting for logs") {
    PreviewScene.logConsole(.preview(lines: []))
}

#Preview("Log console — stream failed") {
    PreviewScene.logConsole(.preview(lines: []), setupError: "The operation couldn’t be completed. Connection refused")
}

// Everything filtered out is a different empty state from having no logs at all.
#Preview("Log console — no match") {
    PreviewScene.logConsole(.preview(query: "nothing matches this"))
}

#Preview("Log console — errors only") {
    PreviewScene.logConsole(.preview(minimumLevel: .error))
}

#Preview("Log console — warnings and above") {
    PreviewScene.logConsole(.preview(minimumLevel: .warning))
}

#Preview("Log console — paused") {
    PreviewScene.logConsole(.preview(paused: true))
}

#Preview("Log console — paused with pending") {
    PreviewScene.logConsole(.preview(
        paused: true,
        pendingLines: [
            "2026-08-04T09:12:11 INFO reachy_mini.camera: producer registered",
            "2026-08-04T09:12:12 INFO reachy_mini.camera: streaming",
        ]
    ))
}
