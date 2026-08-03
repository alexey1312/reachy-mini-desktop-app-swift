import ReachyKit
import ReachyMedia
import SwiftUI

/// Robot camera + two-way audio over WebRTC. Video and robot audio play as
/// soon as the session negotiates; the mic button unmutes the client → robot
/// audio uplink (robot speaker). A joystick overlay drives head yaw/pitch so
/// you can look around without leaving the video.
struct CameraScreen: View {
    let address: RobotAddress

    @State private var session: CameraSession?
    @State private var teleop: SetTargetClient?
    @State private var target = SetTargetClient.Target()
    @State private var setupError: String?

    /// Same comfortable head range as `ControllerScreen`; the daemon clamps anyway.
    private let headAngle = 40.0 * .pi / 180

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraVideoView(track: session?.videoTrack)
            overlay
        }
        .safeAreaInset(edge: .bottom) {
            if session?.phase == .streaming {
                JoystickPad { x, y in
                    target.yaw = -x * headAngle
                    target.pitch = y * headAngle
                    push()
                }
                .frame(width: 140, height: 140)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()
            }
        }
        .navigationTitle("Camera")
        .toolbar {
            if let session {
                Button {
                    session.setMicEnabled(!session.isMicEnabled)
                } label: {
                    Label(
                        session.isMicEnabled ? "Mute microphone" : "Unmute microphone",
                        systemImage: session.isMicEnabled ? "mic.fill" : "mic.slash"
                    )
                    .foregroundStyle(session.isMicEnabled ? .red : .secondary)
                }
                .disabled(session.phase != .streaming)
            }
        }
        .onAppear { start() }
        .onDisappear {
            session?.stop()
            session = nil
            let teleop = teleop
            Task { await teleop?.disconnect() }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if let setupError {
            ContentUnavailableView(
                "Camera unavailable",
                systemImage: "video.slash",
                description: Text(setupError)
            )
        } else {
            switch session?.phase {
            case .connecting, nil:
                ProgressView("Connecting…")
                    .tint(.white)
                    .foregroundStyle(.white)
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
    }

    private func start() {
        do {
            let session = try CameraSession(address: address)
            self.session = session
            session.start()
        } catch {
            setupError = "\(error)"
        }
        if let teleop = try? SetTargetClient(address: address) {
            self.teleop = teleop
            Task { await teleop.connect() }
        }
    }

    private func push() {
        guard let teleop else { return }
        let target = target
        Task { await teleop.send(target) }
    }
}
