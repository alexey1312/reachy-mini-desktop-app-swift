import Foundation

/// What the robot can actually do right now, split along the two axes the
/// daemon really gates on.
///
/// Most `/api` routes depend on `get_backend`, which answers 503 whenever the
/// backend is torn down — that is one axis. Motion additionally needs the
/// motors under power: a robot parked in `disabled` accepts every move command,
/// plays the sound, and does not move. Camera and daemon logs sit outside both.
public extension RobotSession {
    var isBackendRunning: Bool {
        lastStatus?.state == .running
    }

    /// Reported by all three backend flavours (robot, MuJoCo, mockup sim).
    var motorMode: Components.Schemas.MotorControlMode? {
        guard let status = lastStatus?.backendStatus else { return nil }
        return status.value1?.motorControlMode
            ?? status.value2?.motorControlMode
            ?? status.value3?.motorControlMode
    }

    /// Gate for anything that moves the robot.
    var isAwake: Bool {
        isBackendRunning && motorMode == .enabled
    }
}
