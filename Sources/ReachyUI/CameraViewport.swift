import ReachyDesign
import ReachyKit
import ReachyMedia
import SwiftUI

/// Robot camera + two-way audio over WebRTC. Video and robot audio play as soon
/// as the session negotiates; the mic button unmutes the client → robot audio
/// uplink (robot speaker). A joystick drives head yaw/pitch so you can look
/// around without leaving the video, and held sideways it turns the body — which
/// is the one thing it leaves behind, so a button beside it undoes that turn once
/// there is one to undo.
struct CameraViewport: View {
    let session: CameraSession
    /// `nil` hides the joystick outright rather than showing one that cannot move
    /// anything.
    var makeTeleop: TeleopFactory?

    @State private var driver: TeleopDriver
    @Environment(\.reachyPreviewMode) private var previewMode

    init(
        session: CameraSession,
        makeTeleop: TeleopFactory? = nil,
        driver: TeleopDriver = TeleopDriver()
    ) {
        self.session = session
        self.makeTeleop = makeTeleop
        _driver = State(initialValue: driver)
    }

    var body: some View {
        CameraVideoView(track: session.videoTrack)
            .overlay(alignment: .center) { status }
            .safeAreaInset(edge: .bottom) { teleopControls }
            .onAppear { connectTeleop() }
            .onDisappear { driver.stop() }
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .connecting:
            ProgressView(.reachy("Connecting…"))
        case .waitingForProducer:
            ContentUnavailableView(
                .reachy("Waiting for camera"),
                systemImage: "video",
                description: Text(.reachy("The robot has not registered a video stream yet."))
            )
        case let .failed(message):
            ContentUnavailableView(
                .reachy("Camera unavailable"),
                systemImage: "video.slash",
                description: Text(message)
            )
        case .streaming:
            EmptyView()
        }
    }

    /// The pad, and beside it the way back from where the pad can leave you.
    ///
    /// Both sit in the bottom inset rather than in `ViewportView`'s floating
    /// cluster: that cluster is built a level up, which does not own this driver
    /// and covers the 3D scene too, where teleop does not apply. Here they also
    /// land under the thumb that just turned the robot.
    @ViewBuilder
    private var teleopControls: some View {
        // No factory means this connection carries no teleop at all, so the
        // joystick is absent rather than offered inert.
        if session.phase == .streaming, makeTeleop != nil {
            HStack(spacing: Space.md) {
                recenterButton
                JoystickPad(mapping: driver.mapping) { driver.apply($0) }
                    .frame(width: 140, height: 140)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding()
            .animation(Motion.stateChange, value: driver.isBodyTurned)
        }
    }

    /// Offered only once the body is actually turned — at neutral there is nothing
    /// to return from, and this screen has no other readout of where the robot is
    /// facing, so the button appearing *is* the notice that it has been left off
    /// centre.
    ///
    /// The return is smooth without anything here doing so: `reset()` moves a
    /// goal, and both transports walk their emitted pose toward it under
    /// `TargetSlewLimiter`. Easing it a second time on this side would fight the
    /// pacer that already does it.
    @ViewBuilder
    private var recenterButton: some View {
        if driver.isBodyTurned {
            Button {
                driver.reset()
            } label: {
                Label(.reachy("Reset to neutral"), systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
            }
            .viewportControlStyle()
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func connectTeleop() {
        guard !previewMode, let makeTeleop else { return }
        try? driver.start(makeTeleop)
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
                session
                    .isMicEnabled ? String(localized: .reachy("Mute microphone")) :
                    String(localized: .reachy("Unmute microphone")),
                systemImage: session.isMicEnabled ? "mic.fill" : "mic.slash"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(session.isMicEnabled ? .red : .secondary)
        }
        .viewportControlStyle()
        .disabled(session.phase != .streaming)
    }
}
