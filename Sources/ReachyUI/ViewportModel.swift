import Observation
import ReachyKit
import ReachyMedia
import ReachyScene

/// Owns the two live views of the robot — the 3D model and the camera — and
/// guarantees that only one of them is running.
///
/// The guarantee is the whole point: a viewport that is always on screen would
/// otherwise hold a WebRTC peer connection and a state-stream socket open for as
/// long as the app is in the foreground.
@MainActor
@Observable
final class ViewportModel {
    enum Content: String, CaseIterable, Identifiable {
        case scene
        case camera

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .scene: "3D model"
            case .camera: "Camera"
            }
        }

        var systemImage: String {
            switch self {
            case .scene: "cube.transparent"
            case .camera: "video"
            }
        }
    }

    private(set) var content: Content = .scene
    private(set) var sceneModel: RobotSceneModel?
    private(set) var cameraSession: CameraSession?
    /// Set when a transport could not even be constructed — a bad address, not a
    /// failure to reach the robot.
    private(set) var setupError: String?

    private(set) var address: RobotAddress?
    private var isActive = false

    /// Re-attaching to the same address is a no-op, so a SwiftUI redraw cannot
    /// restart the download. A different address tears everything down first —
    /// one robot can appear at several addresses, but the geometry is per robot.
    func attach(to address: RobotAddress) {
        guard self.address != address else { return }
        detach()
        self.address = address
        activate()
    }

    func detach() {
        sceneModel?.stop()
        sceneModel = nil
        cameraSession?.stop()
        cameraSession = nil
        address = nil
        setupError = nil
    }

    func setContent(_ next: Content) {
        guard content != next else { return }
        content = next
        activate()
    }

    /// The single lever for "is the viewport on screen": the Live tab's appearance
    /// on compact, the scene phase everywhere.
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if active {
            activate()
        } else {
            suspend()
        }
    }

    /// Starts whichever engine `content` names and shuts the other one down.
    private func activate() {
        guard isActive, let address else { return }
        setupError = nil
        switch content {
        case .scene:
            stopCamera()
            startScene(at: address)
        case .camera:
            // Paused rather than stopped: the meshes stay in memory, so coming
            // back to 3D does not re-download the robot's description.
            sceneModel?.pauseStream()
            startCamera(at: address)
        }
    }

    private func suspend() {
        sceneModel?.pauseStream()
        stopCamera()
    }

    private func startScene(at address: RobotAddress) {
        if sceneModel == nil {
            guard let connection = try? RobotConnection(address: address) else {
                setupError = "Could not reach \(address.host)"
                return
            }
            sceneModel = RobotSceneModel(address: address, client: connection)
        }
        // Both are idempotent; whichever applies at this point is the one that runs.
        sceneModel?.start()
        sceneModel?.resumeStream()
    }

    private func startCamera(at address: RobotAddress) {
        guard cameraSession == nil else { return }
        guard let session = try? CameraSession(address: address) else {
            setupError = "Could not reach \(address.host)"
            return
        }
        cameraSession = session
        session.start()
    }

    /// WebRTC has no cheap pause — a session that is not on screen is dropped and
    /// renegotiated from scratch next time.
    private func stopCamera() {
        cameraSession?.stop()
        cameraSession = nil
    }
}

#if DEBUG
    extension ViewportModel {
        /// Assembled rather than attached: `attach(to:)` would build a real `RobotConnection` and
        /// a real `CameraSession`. Lives here because every field below is `private(set)`.
        static func preview(
            content: Content = .scene,
            sceneModel: RobotSceneModel? = nil,
            cameraSession: CameraSession? = nil,
            setupError: String? = nil,
            address: RobotAddress? = RobotAddress(host: "192.168.1.42")
        ) -> ViewportModel {
            let model = ViewportModel()
            model.content = content
            model.sceneModel = sceneModel
            model.cameraSession = cameraSession
            model.setupError = setupError
            model.address = address
            return model
        }
    }
#endif
