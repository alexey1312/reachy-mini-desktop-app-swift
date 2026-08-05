import Foundation
@testable import ReachyKit
import Testing

@Suite("Target slew limiter")
struct TargetSlewLimiterTests {
    private let limiter = TargetSlewLimiter()
    private let tick = Duration.milliseconds(33)
    private let tickSeconds = 0.033

    @Test("a step is bounded by the axis rate")
    func stepIsBounded() {
        let next = limiter.next(current: .init(), goal: .init(bodyYaw: .pi), dt: tick)
        #expect(next.bodyYaw > 0)
        #expect(next.bodyYaw <= limiter.bodyYawRate * tickSeconds + 1e-9)
    }

    @Test("iterating converges on the goal without overshoot")
    func converges() {
        let goal = SetTargetClient.Target(yaw: 0.7)
        var current = SetTargetClient.Target()
        var previous = -1.0
        for _ in 0 ..< 200 {
            current = limiter.next(current: current, goal: goal, dt: tick)
            #expect(current.yaw >= previous)
            #expect(current.yaw <= goal.yaw + 1e-9)
            previous = current.yaw
        }
        #expect(abs(current.yaw - goal.yaw) < 1e-3)
    }

    @Test("zero elapsed time moves nothing")
    func zeroDuration() {
        let current = SetTargetClient.Target(yaw: 0.2)
        #expect(limiter.next(current: current, goal: .init(), dt: .zero) == current)
    }

    /// Far from the goal the rate ceiling binds; close in the exponential does, and
    /// the step is smaller. That deceleration is what a plain rate limit lacks, and
    /// it is the difference between "slower snap" and "no snap".
    @Test("the approach decelerates near the goal")
    func softLanding() {
        let far = limiter.next(current: .init(), goal: .init(yaw: 1.0), dt: tick).yaw
        let near = limiter.next(current: .init(), goal: .init(yaw: 0.01), dt: tick).yaw
        #expect(near < far)
        #expect(near < limiter.headAngularRate * tickSeconds)
    }

    /// The behaviour the whole change exists for. Bounds are loose on purpose —
    /// this asserts "neither a snap nor a crawl", not a tuned constant.
    @Test("a released head reaches neutral in well under a second")
    func returnFromFullDeflection() {
        var current = SetTargetClient.Target(yaw: 40 * .pi / 180)
        var ticks = 0
        while abs(current.yaw) > 0.5 * .pi / 180, ticks < 100 {
            current = limiter.next(current: current, goal: .init(), dt: tick)
            ticks += 1
        }
        #expect(ticks > 8)
        #expect(ticks < 40)
    }

    /// A field added to `Target` without an entry in the axis table would slip past
    /// the limiter in silence. This is what notices.
    @Test("every axis of Target is limited")
    func everyAxisIsCovered() {
        let fields = Mirror(reflecting: SetTargetClient.Target()).children.count
        #expect(fields == TargetSlewLimiter.axes.count)

        for (axis, _) in TargetSlewLimiter.axes {
            var goal = SetTargetClient.Target()
            goal[keyPath: axis] = 1.0
            let next = limiter.next(current: .init(), goal: goal, dt: tick)
            #expect(next[keyPath: axis] > 0)
            #expect(next[keyPath: axis] < 1.0)
        }
    }

    @Test("convergence is reported only when every axis has arrived")
    func convergence() {
        let goal = SetTargetClient.Target(yaw: 0.5)
        #expect(limiter.hasConverged(goal, to: goal))
        #expect(!limiter.hasConverged(.init(), to: goal))
    }
}
