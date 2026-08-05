import ReachyKit
import ReachyMedia
import SwiftUI

/// Robot camera + two-way audio over WebRTC. Video and robot audio play as soon
/// as the session negotiates; the mic button unmutes the client → robot audio
/// uplink (robot speaker). A joystick drives head yaw/pitch so you can look
/// around without leaving the video.
struct CameraViewport: View {
    let session: CameraSession
    let address: RobotAddress

    @State private var teleop: SetTargetClient?
    @State private var target = SetTargetClient.Target()
    @Environment(\.reachyPreviewMode) private var previewMode

    /// Same comfortable head range as `ControllerScreen`; the daemon clamps anyway.
    private let headAngle = 40.0 * .pi / 180

    var body: some View {
        CameraVideoView(track: session.videoTrack)
            .overlay(alignment: .center) { status }
            .safeAreaInset(edge: .bottom) { joystick }
            .onAppear { connectTeleop() }
            .onDisappear {
                let teleop = teleop
                self.teleop = nil
                Task { await teleop?.disconnect() }
            }
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
            JoystickPad { deflection in
                target.yaw = -deflection.x * headAngle
                target.pitch = deflection.y * headAngle
                push()
            }
            .frame(width: 140, height: 140)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding()
        }
    }

    private func connectTeleop() {
        guard !previewMode else { return }
        guard teleop == nil, let client = try? SetTargetClient(address: address) else { return }
        teleop = client
        Task { await client.connect() }
    }

    private func push() {
        guard let teleop else { return }
        let target = target
        Task { await teleop.send(target) }
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
