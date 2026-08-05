import Foundation
import ReachyKit

/// Owns the live teleop target for a screen: the joystick's head pose, the sliders,
/// and the body yaw it integrates while the knob sits in a rotation zone.
///
/// The integration lives here rather than in `SetTargetClient` because
/// `ControllerScreen`'s body-yaw slider is bound to this same target — an angle
/// drifting inside the actor would leave the slider disagreeing with the robot.
@MainActor
@Observable
final class TeleopDriver {
    /// Every write reaches the robot as a goal, so a slider jump is as smooth as a
    /// joystick release.
    var target: SetTargetClient.Target {
        didSet { push() }
    }

    let mapping: JoystickMapping
    private(set) var bodyYawRate: Double = 0

    private static let tick = Duration.milliseconds(20)
    private var client: SetTargetClient?
    private var rotationTask: Task<Void, Never>?

    init(
        target: SetTargetClient.Target = SetTargetClient.Target(),
        mapping: JoystickMapping = JoystickMapping()
    ) {
        self.target = target
        self.mapping = mapping
    }

    func start(address: RobotAddress) throws {
        guard client == nil else { return }
        let client = try SetTargetClient(address: address)
        self.client = client
        Task { await client.connect() }
    }

    func stop() {
        stopRotation()
        let client = client
        self.client = nil
        Task { await client?.disconnect() }
    }

    /// Head follows the deflection; past the rotation zone the body starts turning.
    ///
    /// Written as one assignment on purpose: `didSet` fires per write, and a gesture
    /// arrives at screen rate, so two writes would double the pushes for nothing.
    func apply(_ deflection: JoystickDeflection) {
        var next = target
        next.yaw = mapping.headYaw(deflection)
        next.pitch = mapping.headPitch(deflection)
        target = next
        setRotation(rate: mapping.bodyYawRate(deflection))
    }

    func reset() {
        stopRotation()
        target = .init()
    }

    /// One integration step. Called by the ticker, and by tests without one.
    func integrateRotation(seconds: Double) {
        guard bodyYawRate != 0 else { return }
        target.bodyYaw = (target.bodyYaw + bodyYawRate * seconds).clamped(to: -.pi ... .pi)
    }

    private func setRotation(rate: Double) {
        bodyYawRate = rate
        guard rate != 0 else {
            stopRotation()
            return
        }
        guard rotationTask == nil else { return }
        rotationTask = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                let now = ContinuousClock.now
                let elapsed = last.duration(to: now)
                last = now
                guard let self else { return }
                integrateRotation(seconds: elapsed.inSeconds)
            }
        }
    }

    private func stopRotation() {
        bodyYawRate = 0
        rotationTask?.cancel()
        rotationTask = nil
    }

    private func push() {
        guard let client else { return }
        let target = target
        Task { await client.send(target) }
    }
}

private extension Duration {
    var inSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}
