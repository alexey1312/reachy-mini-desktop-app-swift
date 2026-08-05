import Foundation

/// What this session leaves behind for the widget.
///
/// A widget extension is a separate process, woken for a moment and given no way
/// to reach a robot — no state socket, no peer connection, not even the app's own
/// container. Everything it shows comes from here.
extension RobotSession {
    /// Records the current state under the connected robot's name.
    ///
    /// Called wherever the session already learns something — the handshake and
    /// each status poll — so the widget costs the robot nothing of its own. The
    /// date is injectable because a snapshot's whole value is when it was taken.
    func recordSnapshot(identity: RobotIdentity, at date: Date = Date()) {
        // Naming the running app would cost a round trip of its own every poll —
        // it is not in the status the session already has. So the poll carries
        // forward what `recordRunningApp` last learned rather than blanking it:
        // this does not learn it, and therefore must not forget it.
        let running = snapshots.current
        snapshots.write(RobotSnapshot(
            robotName: robotName(from: identity),
            isAwake: isAwake,
            runningApp: running?.runningApp,
            runningAppName: running?.runningAppName,
            takenAt: date
        ))
    }

    /// The daemon reports an empty string for a robot it was never given a name
    /// for, which is a name no user typed and none should be shown.
    private func robotName(from identity: RobotIdentity) -> String? {
        for candidate in [identity.name, lastStatus?.robotName] {
            if let candidate, !candidate.isEmpty {
                return candidate
            }
        }
        return nil
    }
}
