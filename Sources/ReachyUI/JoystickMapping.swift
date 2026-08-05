import Foundation

/// Where the knob sits, normalized to the pad's radius.
struct JoystickDeflection: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0

    static let zero = JoystickDeflection()
}

/// Turns a joystick deflection into a head pose and a body rotation speed.
///
/// The first `rotationThreshold` of sideways travel is head yaw; past it the head
/// holds at its limit and the body starts turning, at a speed that grows from zero
/// at the boundary. `maxBodyYawRate` must stay below `TargetSlewLimiter.bodyYawRate`
/// or the limiter would cap the turn rather than merely smooth it.
struct JoystickMapping: Equatable, Sendable {
    var rotationThreshold = 0.7
    /// Comfortable head range; the daemon clamps anyway.
    var headAngle = 40.0 * .pi / 180
    /// Radians per second at full sideways deflection — a half turn in three seconds.
    var maxBodyYawRate = 60.0 * .pi / 180

    func headYaw(_ deflection: JoystickDeflection) -> Double {
        -(deflection.x / rotationThreshold).clamped(to: -1 ... 1) * headAngle
    }

    func headPitch(_ deflection: JoystickDeflection) -> Double {
        deflection.y * headAngle
    }

    /// Radians per second, zero inside the head zone. Signed like `headYaw`, so the
    /// head and the body turn the same way for the same push.
    func bodyYawRate(_ deflection: JoystickDeflection) -> Double {
        let over = abs(deflection.x) - rotationThreshold
        guard over > 0 else { return 0 }
        let ramp = (over / (1 - rotationThreshold)).clamped(to: 0 ... 1)
        return deflection.x < 0 ? ramp * maxBodyYawRate : -ramp * maxBodyYawRate
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
