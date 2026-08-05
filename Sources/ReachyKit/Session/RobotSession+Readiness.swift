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
        lastStatus?.isBackendRunning ?? false
    }

    /// Reported by all three backend flavours (robot, MuJoCo, mockup sim).
    var motorMode: Components.Schemas.MotorControlMode? {
        lastStatus?.motorControlMode
    }

    /// Gate for anything that moves the robot.
    var isAwake: Bool {
        lastStatus?.isAwake ?? false
    }

    /// The daemon's own fault text, e.g. "Power supply not connected".
    ///
    /// `Daemon.status()` copies a backend error up to the top level and forces
    /// `state` to `error`, so the top-level field is the one that usually carries
    /// it; the per-flavour fields are the fallback.
    var backendFault: String? {
        let candidates = [
            lastStatus?.error,
            lastStatus?.backendStatus?.value1?.error,
            lastStatus?.backendStatus?.value2?.error,
            lastStatus?.backendStatus?.value3?.error,
        ]
        return candidates
            .compactMap(\.self)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A wired unit has no camera at all, so the UI hides video rather than
    /// offering something that can only fail.
    var hasCamera: Bool {
        lastStatus?.wirelessVersion == true || lastStatus?.simulationEnabled == true
    }

    /// `/wifi/*` and `/update/*` are mounted only under `--wireless-version`, so a
    /// Lite robot answers 404 to all of them. Hide those controls rather than let
    /// the user press a button that cannot work.
    var supportsWirelessFeatures: Bool {
        lastStatus?.wirelessVersion == true
    }
}
