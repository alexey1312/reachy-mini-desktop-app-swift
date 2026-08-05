import Foundation
import simd

/// Live teleop over the data channel.
///
/// `set_full_target` carries head, antennas and body yaw in one message — the
/// same three things the LAN socket sends as one `FullBodyTarget`, where
/// `set_target` alone would need `set_body_yaw` and `set_antennas` beside it and
/// turn every frame into three.
///
/// It is *sent* rather than performed. The daemon does answer
/// `{"status":"ok","command":"set_full_target"}`, but at gesture rate a reply
/// budget would serialise each frame behind the previous one's answer, because
/// commands of one name take turns on this channel by design. The echo arrives
/// with no waiter registered and is dropped, which is what should happen to an
/// answer nobody is waiting on.
public actor RemoteTeleopChannel: TeleopChannel {
    private let control: RemoteControlChannel
    private let minSendInterval: Duration
    private var lastSendAt: ContinuousClock.Instant?

    public init(control: RemoteControlChannel, minSendInterval: Duration = .milliseconds(33)) {
        self.control = control
        self.minSendInterval = minSendInterval
    }

    /// Both no-ops. This rides a channel the peer connection opened long before a
    /// joystick existed, and closing it would end the session the robot is being
    /// driven over — the camera and every command with it.
    public func connect() async {}

    public func disconnect() async {}

    /// Drops the frame if the previous one went out under `minSendInterval` ago,
    /// exactly as the LAN client does: the UI emits at gesture rate, the wire
    /// should not.
    public func send(_ target: TeleopTarget) async {
        let now = ContinuousClock.now
        if let lastSendAt, lastSendAt.duration(to: now) < minSendInterval {
            return
        }
        lastSendAt = now
        try? await control.send("set_full_target", payload: Self.payload(for: target))
    }

    /// The same pose the LAN route builds, expressed the way this channel wants
    /// it.
    ///
    /// `/api/move/ws/set_target` sends XYZRPY and the daemon composes the matrix
    /// itself with `R.from_euler("xyz", [roll, pitch, yaw])` — lowercase, so
    /// extrinsic, so `Rz(yaw)·Ry(pitch)·Rx(roll)`, which is exactly
    /// ``RigidTransform/rotation(rpy:)``. Here the matrix is composed on this side
    /// and flattened row by row, because `set_full_target` takes
    /// `np.array(cmd.head).reshape(4, 4)`.
    ///
    /// The antennas are passed through in the order the LAN client uses. Both
    /// routes hand the pair straight to `set_target_antenna_joint_positions`
    /// without reordering, so whatever that order means physically, it means the
    /// same thing on both transports.
    static func payload(for target: TeleopTarget) -> [String: RemoteValue] {
        let pose = RigidTransform.transform(
            translation: SIMD3(target.x, target.y, target.z),
            rpy: SIMD3(target.roll, target.pitch, target.yaw)
        )
        return [
            "head": .array(RigidTransform.rowMajorValues(pose).map(RemoteValue.number)),
            "antennas": .array([.number(target.antennaLeft), .number(target.antennaRight)]),
            "body_yaw": .number(target.bodyYaw),
        ]
    }
}

extension RemoteRobotConnection: TeleopClient {
    public nonisolated func makeTeleop() throws -> any TeleopChannel {
        RemoteTeleopChannel(control: control)
    }
}
