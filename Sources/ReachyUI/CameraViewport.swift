import ReachyKit
import ReachyMedia
import SwiftUI

/// Robot camera + two-way audio over WebRTC. Video and robot audio play as soon
/// as the session negotiates; the mic button unmutes the client → robot audio
/// uplink (robot speaker). A joystick drives head yaw/pitch so you can look
/// around without leaving the video, and held sideways it turns the body.
struct CameraViewport: View {
    let session: CameraSession
    let address: RobotAddress

    @State private var driver: TeleopDriver
    @Environment(\.reachyPreviewMode) private var previewMode

    init(session: CameraSession, address: RobotAddress, driver: TeleopDriver = TeleopDriver()) {
        self.session = session
        self.address = address
        _driver = State(initialValue: driver)
    }

    var body: some View {
        CameraVideoView(track: session.videoTrack)
            .overlay(alignment: .center) { status }
            .safeAreaInset(edge: .bottom) { joystick }
            .onAppear { connectTeleop() }
            .onDisappear { driver.stop() }
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .connecting:
            ProgressView("Connecting…")
        case .waitingForProducer:
            ContentUnavailableView(
                "Waiting for camera",
                systemImage: "video",
                description: Text("The robot has not registered a video stream yet.")
            )
        case let .failed(message):
            ContentUnavailableView(
                "Camera unavailable",
                systemImage: "video.slash",
                description: Text(message)
            )
        case .streaming:
            EmptyView()
        }
    }

    @ViewBuilder
    private var joystick: some View {
        if session.phase == .streaming {
            JoystickPad(mapping: driver.mapping) { driver.apply($0) }
                .frame(width: 140, height: 140)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()
        }
    }

    private func connectTeleop() {
        guard !previewMode else { return }
        try? driver.start(address: address)
    }
}

/// Unmutes the client → robot audio uplink. Lives beside the viewport switcher
/// rather than inside the video, so the floating controls stay in one cluster.
struct CameraMicButton: View {
    let session: CameraSession

    var body: some View {
        Button {
            session.setMicEnabled(!session.isMicEnabled)
        } label: {
            Label(
                session.isMicEnabled ? "Mute microphone" : "Unmute microphone",
                systemImage: session.isMicEnabled ? "mic.fill" : "mic.slash"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(session.isMicEnabled ? .red : .secondary)
        }
        .viewportControlStyle()
        .disabled(session.phase != .streaming)
    }
}
