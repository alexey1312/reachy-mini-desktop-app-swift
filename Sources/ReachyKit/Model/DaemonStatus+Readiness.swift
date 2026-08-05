import Foundation

/// Reading readiness off a status, with no session holding it.
///
/// `RobotSession` derives the same two things from the status it polls, and an
/// App Intent has to derive them from a status it fetched once — a second copy of
/// the rule is how the two would come to disagree about what "awake" means.
public extension Components.Schemas.DaemonStatus {
    /// Reported by all three backend flavours (robot, MuJoCo, mockup sim).
    var motorControlMode: Components.Schemas.MotorControlMode? {
        guard let status = backendStatus else { return nil }
        return status.value1?.motorControlMode
            ?? status.value2?.motorControlMode
            ?? status.value3?.motorControlMode
    }

    var isBackendRunning: Bool {
        state == .running
    }

    /// Gate for anything that moves the robot. Both halves matter: a robot parked
    /// in `disabled` accepts every move command, plays the sound, and does not
    /// move.
    var isAwake: Bool {
        isBackendRunning && motorControlMode == .enabled
    }
}
