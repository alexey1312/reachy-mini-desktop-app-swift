import ReachyKit
@testable import ReachyUI
import SwiftUI

#Preview("Connection — searching") {
    PreviewScene.connection(.preview(phase: .idle, status: nil, address: nil))
}

#Preview("Connection — robots found") {
    PreviewScene.connection(.preview(phase: .idle, status: nil, address: nil), browser: .preview())
}

// Denied Local Network permission looks exactly like an empty network from the API, so the screen
// has to say so itself.
#Preview("Connection — permission denied") {
    PreviewScene.connection(
        .preview(phase: .idle, status: nil, address: nil),
        browser: .preview(names: [], permissionDenied: true)
    )
}

#Preview("Connection — probing") {
    PreviewScene.connection(.preview(phase: .connecting(.handshaking), status: nil, address: nil))
}

// A decision the user has to make hides discovery entirely: the list underneath would only
// compete with start / continue / cancel.
#Preview("Connection — needs a decision") {
    PreviewScene.connection(
        .preview(
            phase: .connecting(.backendUnavailable(.preview, daemonMessage: "Backend not running")),
            status: nil,
            address: nil
        )
    )
}

#Preview("Connection — connect failed") {
    PreviewScene.connection(
        .preview(
            phase: .connecting(.failed(.connect, message: "Could not connect to the server.")),
            status: nil,
            address: nil
        )
    )
}

#Preview("Connection — error") {
    PreviewScene.connection(
        .preview(phase: .idle, status: nil, address: nil, error: "The daemon refused the handshake."),
        browser: .preview()
    )
}

#Preview("Connection — reconnect paused") {
    PreviewScene.connection(
        .preview(phase: .idle, status: nil, address: nil, automaticConnectionAllowed: false),
        browser: .preview()
    )
}

#Preview("Connection — manual address typed") {
    PreviewScene.connection(
        .preview(phase: .idle, status: nil, address: nil),
        browser: .preview(names: []),
        manualInput: "192.168.1.42"
    )
}

#Preview("Connection — manual address invalid") {
    PreviewScene.connection(
        .preview(phase: .idle, status: nil, address: nil),
        browser: .preview(names: []),
        manualInput: "not an address"
    )
}
