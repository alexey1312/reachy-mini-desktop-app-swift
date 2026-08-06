import ReachyKit
import ReachyMedia
import SwiftUI

/// The viewport, full screen on every platform.
///
/// Teleop already lives here — `CameraViewport` hangs `JoystickPad` off the
/// factory this passes down — so the full controller belongs behind this tab's
/// bar rather than two taps deep in a `Form` on another one.
struct LiveTab: View {
    let session: RobotSession
    let viewport: ViewportModel
    let router: ReachyRouter
    let remoteLink: RemoteRobotLink?

    var body: some View {
        @Bindable var router = router
        return NavigationStack {
            // No `ignoresSafeArea` here: the camera hangs its joystick off a bottom
            // safe-area inset, which would then be laid out under the tab bar and
            // clipped.
            content
                .navigationTitle("Live")
                .hfAccountToolbar(isPresented: $router.showsAccount)
                .toolbar {
                    if session.canTeleoperate {
                        ToolbarItem {
                            NavigationLink {
                                ControllerScreen(session: session)
                            } label: {
                                Label("Controller", systemImage: "gamecontroller")
                            }
                        }
                    }
                }
        }
    }

    /// Both streams would keep working while the robot sleeps — the camera hangs
    /// off `get_daemon` and the state stream off a running backend — but working is
    /// not the same as worth having. A motionless pose and a still frame cost the
    /// robot's radio and this phone's battery to show nothing, and a switcher
    /// between two inert views is a control that leads nowhere. So the tab keeps
    /// its place and offers the one thing that changes the situation.
    @ViewBuilder
    private var content: some View {
        if viewportTarget == nil {
            LiveUnavailableView()
        } else if session.isAwake {
            ViewportView(model: viewport, offersCamera: session.hasCamera, makeTeleop: makeTeleop)
        } else {
            // Pinned to the top: the banner is the tab's only content, and a lone
            // card floating in the middle of an empty screen reads as a view that
            // failed to load rather than as a status about the robot.
            AsleepBanner(session: session)
                .padding()
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var viewportTarget: ViewportModel.Source? {
        RootViewportTarget.source(session: session, remoteLink: remoteLink)
    }

    /// Absent where this connection carries no teleop, so the joystick is not
    /// offered rather than offered inert.
    private var makeTeleop: TeleopFactory? {
        guard session.canTeleoperate else { return nil }
        return { [session] in try session.makeTeleop() }
    }
}
