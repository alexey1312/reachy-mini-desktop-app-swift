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
    ///
    /// Over the relay the question is already settled: the peer connection that
    /// carries the commands is the one carrying the video, so there is a camera
    /// by construction. `wirelessVersion` cannot answer it there — it is reported
    /// `false` on purpose, to keep `/wifi/*` and `/update/*` closed.
    var hasCamera: Bool {
        isRemote || lastStatus?.wirelessVersion == true || lastStatus?.simulationEnabled == true
    }

    /// The 3D model is built from URDF and STL served over `/api/kinematics/*`,
    /// which is exactly what a relay session cannot reach — the one feature ADR
    /// 0003 gives up outright.
    var canRenderScene: Bool {
        address != nil
    }

    /// Recorded moves are `/api/move/play/*` and the dataset index beside them,
    /// both HTTP-only. The data channel can play an *uploaded* move and nothing
    /// from the robot's own library.
    ///
    /// Derived from the link rather than probed with `client is any MovesClient`
    /// because `listMoves` and friends still live on `RobotAPIClient` behind
    /// throwing defaults; lifting them onto a sub-protocol touches every test
    /// double and belongs in its own change.
    var canPlayMoves: Bool {
        address != nil
    }

    /// `/wifi/*` and `/update/*` are mounted only under `--wireless-version`, so a
    /// Lite robot answers 404 to all of them. Hide those controls rather than let
    /// the user press a button that cannot work.
    var supportsWirelessFeatures: Bool {
        lastStatus?.wirelessVersion == true
    }
}
