import Foundation
import ReachyKit

/// Tearing the robot backend down, with no session around it.
///
/// The twin of `RobotSession.powerOff`, and deliberately not the same code — the
/// split `RobotAppLauncher` records at greater length. That one reads the running
/// app off state the session is already holding and reports each half's failure
/// onto a screen; this has neither, so it asks the daemon afresh and has nowhere
/// to put a sentence.
public struct RobotShutdown: Sendable {
    private let apps: any RobotAppsClient
    private let daemon: any RobotAPIClient

    public init(client: any RobotAPIClient & RobotAppsClient) {
        apps = client
        daemon = client
    }

    /// Test seam: the two halves, with no client to build them from.
    init(apps: any RobotAppsClient, daemon: any RobotAPIClient) {
        self.apps = apps
        self.daemon = daemon
    }

    /// Stops whatever holds the robot, then asks the daemon to shut the backend
    /// down with a sleep on the way.
    ///
    /// **The app is stopped here because the daemon will not.** Its teardown drops
    /// the media server and the JSON-RPC relay and never touches the app manager,
    /// so an app left running has its backend go out from under it.
    ///
    /// The parking itself is the daemon's: `stop?goto_sleep=true` enables the
    /// motors, *awaits* the sleep animation and only then cuts power, which is more
    /// than `RobotPower.sleep()` does. A client-side sleep beforehand would add
    /// nothing and delay it.
    ///
    /// Failing to stop the app does not abort: the robot's body is parked either
    /// way, and that is the half that matters. `RobotSession.powerOff` reports that
    /// failure because it has a screen to report it on — an intent has one sentence
    /// and it belongs to the shutdown.
    public func perform() async throws {
        if let running = try? await apps.currentAppStatus(), running.isBusy {
            try? await apps.stopCurrentApp()
        }
        // Returns as soon as the daemon has accepted the job. Nothing polls it
        // afterwards: the caller is an intent, and waiting out a sixty-second
        // budget in a process that has seconds would fail with the work already
        // done and no way to say so.
        try await daemon.stopDaemon(gotoSleep: true)
    }
}
