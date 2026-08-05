import Foundation
import ReachyKit

/// One robot picked off the remote list, assembled into something a
/// `RobotSession` can be handed.
///
/// Four pieces that only fit together here, because this is the one module that
/// sees both halves: the relay carries signaling (`ReachyKit`), the peer
/// connection carries the session (`ReachyMedia`), its data channel carries the
/// commands, and `RemoteRobotConnection` dresses those as the daemon API.
///
/// The camera comes for free — it is the same peer connection. The 3D scene does
/// not: it is built from URDF and STL served over the daemon's HTTP API, which is
/// exactly what a remote session cannot reach.
///
/// Untested, like the rest of this module: every piece below the relay needs a
/// live peer connection. The pieces either side of it are covered —
/// `CentralSignalingTransport` against stubbed HTTP, `RemoteRobotConnection`
/// against a scripted channel.
@MainActor
public final class RemoteRobotLink {
    /// Also the video: one peer connection carries both.
    public let camera: CameraSession
    /// Hand this to `RobotSession.connect(using:)`.
    public let client: RemoteRobotConnection

    public convenience init(robot: CentralRobot, relay: CentralRelayClient) {
        self.init(
            camera: CameraSession(
                signaling: CentralSignalingTransport(relay: relay, robotPeerID: robot.peerID)
            ),
            // Central knows the robot's name and the channel does not, so the
            // listing the user picked from is where it comes from.
            robotName: robot.displayName
        )
    }

    private init(camera: CameraSession, robotName: String?) {
        self.camera = camera
        client = RemoteRobotConnection(channel: camera.dataChannel, robotName: robotName)
    }

    /// Opens the relay stream and asks central for a session. Nothing reaches the
    /// robot until this runs — `RemoteRobotConnection` will simply wait on a
    /// channel that has not been opened yet.
    public func start() {
        camera.start()
    }

    public func stop() {
        camera.stop()
    }
}

#if DEBUG
    public extension RemoteRobotLink {
        /// A link around a camera that is already in some phase, for the one state
        /// only a live relay session can otherwise reach: the root view holds this
        /// as `@State`, so without a seam every preview of a remote robot renders
        /// "No live view" — the very bug this was written to fix.
        ///
        /// Inert, like `CameraSession.preview`: nothing is negotiated until
        /// `start()`, which no preview calls.
        static func preview(camera: CameraSession = .preview(.waitingForProducer)) -> RemoteRobotLink {
            RemoteRobotLink(camera: camera, robotName: "Reachy Mini")
        }
    }
#endif
