import Foundation

/// The wake and sleep protocols, with no session around them.
///
/// `RobotSession` owns them for the app, where a failure belongs on a screen and
/// a transition has to be latched against a double tap. An App Intent has neither
/// a screen nor a second tap to guard against — it has seconds, one client, and a
/// caller that needs to be told what happened. So the protocol itself lives here
/// and both callers share it, rather than the sequence existing twice and drifting.
///
/// Neither transition is a single call: `/move/play/*` only plays an animation and
/// never touches the motor control mode, so enabling and cutting power is the
/// caller's job — and the order is what keeps the robot's head off the desk.
public struct RobotPower: Sendable {
    private let client: any RobotAPIClient
    private let configuration: RobotSession.Configuration

    public init(client: any RobotAPIClient, configuration: RobotSession.Configuration = .init()) {
        self.client = client
        self.configuration = configuration
    }

    /// Motors first, then the animation. An asleep robot accepts the play route,
    /// makes the sound and does not move, which reads as the robot ignoring you.
    public func wake() async throws {
        try await client.setMotorMode(.enabled)
        try await Task.sleep(for: configuration.motorSettleDelay)
        let uuid = try await client.wakeUp()
        await waitForMoveToFinish(uuid)
    }

    /// The animation must finish *before* power is cut, otherwise the head drops
    /// wherever it happens to be.
    public func sleep() async throws {
        let uuid = try await client.gotoSleep()
        await waitForMoveToFinish(uuid)
        try await client.setMotorMode(.disabled)
    }

    /// Polls the daemon's own running-move list until the id is gone.
    ///
    /// A timeout returns normally rather than throwing: parking the motors matters
    /// more than proof the animation ran to the end, and a remote connection
    /// reports no running moves at all by construction.
    private func waitForMoveToFinish(_ uuid: String) async {
        let deadline = ContinuousClock.now + configuration.moveCompletionTimeout
        while ContinuousClock.now < deadline {
            guard let running = try? await client.runningMoveUUIDs() else { return }
            if !running.contains(uuid) {
                return
            }
            try? await Task.sleep(for: configuration.movePollInterval)
        }
    }
}
