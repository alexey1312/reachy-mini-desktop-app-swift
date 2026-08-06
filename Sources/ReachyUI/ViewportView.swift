import ReachyDesign
import ReachyKit
import SwiftUI

/// Opens a teleop stream on demand — a WebSocket on the LAN, the session's own
/// data channel over the relay.
///
/// `@Sendable` because a `View` is, and this is stored on two of them; `@MainActor`
/// because the session it closes over is.
typealias TeleopFactory = @MainActor @Sendable () throws -> any TeleopChannel

/// The one place a live view of the robot is mounted.
///
/// There is deliberately no second instance anywhere: `RobotSceneView` hands the
/// scene's root entity to `RealityView`, and an entity has exactly one parent, so
/// a second viewport would silently steal the robot from the first.
struct ViewportView: View {
    let model: ViewportModel
    /// The robot reports no camera at all on a wired unit — then there is nothing
    /// to switch between and the control is hidden rather than disabled.
    let offersCamera: Bool
    /// `nil` where this connection carries no teleop at all, and then the joystick
    /// is absent rather than inert.
    var makeTeleop: TeleopFactory?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { chrome }
    }

    /// Every floating control hugs the leading edge: on iPad the tab bar floats
    /// over the top centre, and anything trailing-aligned ends up underneath it.
    ///
    /// The group is what lets two neighbouring pieces of chrome be one sheet of
    /// glass rather than two — it costs nothing below iOS 26, where it renders its
    /// content unchanged.
    private var chrome: some View {
        ReachySurfaceGroup(spacing: Space.md) {
            HStack(spacing: Space.md) {
                switcher
                contentControls
            }
        }
        .padding(Space.md)
    }

    @ViewBuilder
    private var contentControls: some View {
        switch model.content {
        case .scene:
            if let sceneModel = model.sceneModel {
                SceneOptionsMenu(model: sceneModel)
            }
        case .camera:
            if let session = model.cameraSession {
                CameraMicButton(session: session)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let setupError = model.setupError {
            ContentUnavailableView(
                .reachy("Viewport unavailable"),
                systemImage: "exclamationmark.triangle",
                description: Text(setupError)
            )
        } else {
            switch model.content {
            case .scene:
                if let reason = model.sceneUnavailableReason {
                    // A reason, not a wait: nothing is coming, so a spinner here
                    // would never resolve.
                    ContentUnavailableView(
                        .reachy("No 3D model"),
                        systemImage: "cube.transparent",
                        description: Text(reason)
                    )
                } else if let sceneModel = model.sceneModel {
                    SceneViewport(model: sceneModel)
                } else {
                    ViewportStatus.loading("Connecting…", progress: nil)
                }
            case .camera:
                if let session = model.cameraSession {
                    CameraViewport(session: session, makeTeleop: makeTeleop)
                } else {
                    ViewportStatus.loading("Connecting…", progress: nil)
                }
            }
        }
    }

    /// What there is to switch between. Over the relay the 3D model does not
    /// exist, so there is one option and the control disappears rather than
    /// offering a dead segment.
    private var options: [ViewportModel.Content] {
        (model.offersScene ? [.scene] : []) + (offersCamera ? [.camera] : [])
    }

    @ViewBuilder
    private var switcher: some View {
        if options.count > 1 {
            Picker(.reachy("Viewport"), selection: Binding(
                get: { model.content },
                set: { model.setContent($0) }
            )) {
                ForEach(options) { content in
                    Label(content.title, systemImage: content.systemImage).tag(content)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
            // A segmented control's track is translucent, so on the camera's black
            // backdrop the unselected segment had no contrast left and read as missing
            // (seen in dark mode). It now carries its own backing like every other
            // floating control here — which is the rule stated at the bottom of this
            // file, and the reason it holds regardless of theme or what is behind it.
            //
            // 3 pt is optical, not rhythm: it is what stops the segmented track from
            // touching the capsule around it.
            .padding(3)
            .reachySurface(.chrome, in: .capsule)
        }
    }
}

/// Shared chrome so the scene and the camera report progress the same way.
enum ViewportStatus {
    /// `@MainActor` because it builds a surface, and `ViewModifier` carries that
    /// isolation in Swift 6.
    @MainActor
    static func loading(_ title: String, progress: Double?) -> some View {
        VStack(spacing: Space.md) {
            if let progress {
                ProgressView(value: progress)
                    .frame(maxWidth: 220)
            } else {
                ProgressView()
            }
            Text(title)
                .font(Typography.detail)
                .foregroundStyle(Tone.quiet.style)
        }
        .padding(20)
        // `Radius.rect` is `.continuous`; this shape used to default to `.circular`,
        // so the reference image moves here. That is the correction, not a
        // regression — `ReachyDesign/AGENTS.md` records it as expected.
        .reachySurface(.chrome, in: Radius.rect(Radius.md))
    }
}

extension View {
    /// Floating controls sit on top of video and 3D alike, so they carry their own
    /// backing rather than relying on whatever is behind them for contrast.
    ///
    /// `@MainActor` because `reachySurface` is: a `ViewModifier`'s initialiser
    /// carries that isolation in Swift 6, and a nonisolated helper cannot return
    /// what it builds.
    @MainActor
    func viewportControlStyle() -> some View {
        font(.title3)
            .padding(Space.sm)
            .reachySurface(.chrome, in: .circle)
    }
}
