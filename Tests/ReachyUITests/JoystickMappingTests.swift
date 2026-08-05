import ReachyKit
@testable import ReachyUI
import Testing

@Suite("Joystick mapping")
struct JoystickMappingTests {
    private let mapping = JoystickMapping()

    @Test("head yaw is linear inside the head zone and saturates past it")
    func headYaw() {
        #expect(mapping.headYaw(.zero) == 0)
        #expect(abs(mapping.headYaw(.init(x: 0.35)) + mapping.headAngle / 2) < 1e-9)
        #expect(abs(mapping.headYaw(.init(x: 0.7)) + mapping.headAngle) < 1e-9)
        #expect(abs(mapping.headYaw(.init(x: 1.0)) + mapping.headAngle) < 1e-9)
    }

    /// Zero at the boundary is the point: entering the rotation zone cannot itself
    /// produce a jolt, because the speed it starts at is nothing.
    @Test("the body starts turning from a standstill at the zone boundary")
    func rotationRamp() {
        #expect(mapping.bodyYawRate(.init(x: 0.7)) == 0)
        #expect(mapping.bodyYawRate(.init(x: 0.5)) == 0)
        #expect(abs(mapping.bodyYawRate(.init(x: 0.85)) + mapping.maxBodyYawRate / 2) < 1e-9)
        #expect(abs(mapping.bodyYawRate(.init(x: 1.0)) + mapping.maxBodyYawRate) < 1e-9)
    }

    @Test("left and right are mirror images")
    func symmetry() {
        #expect(mapping.headYaw(.init(x: -0.5)) == -mapping.headYaw(.init(x: 0.5)))
        #expect(mapping.bodyYawRate(.init(x: -0.9)) == -mapping.bodyYawRate(.init(x: 0.9)))
    }

    /// If the joystick could outrun the limiter, the emitted pose would fall
    /// permanently behind the goal and the body would turn at the limiter's speed
    /// rather than the one the finger asked for.
    @Test("the joystick cannot outrun the slew limiter")
    func staysUnderTheCeiling() {
        #expect(mapping.maxBodyYawRate < TargetSlewLimiter().bodyYawRate)
    }

    @Test("pitch keeps its existing meaning")
    func pitch() {
        #expect(abs(mapping.headPitch(.init(y: 1.0)) - mapping.headAngle) < 1e-9)
        #expect(abs(mapping.headPitch(.init(y: -0.5)) + mapping.headAngle / 2) < 1e-9)
    }
}
