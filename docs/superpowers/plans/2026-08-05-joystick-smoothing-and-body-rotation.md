# Joystick smoothing and body rotation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every teleop command reach the robot as a bounded, decelerating movement instead of a step, and let a
sideways-held joystick turn the robot's body.

**Architecture:** A pure `TargetSlewLimiter` in ReachyKit bounds how fast an emitted pose may walk toward its goal.
`SetTargetClient` stops being a transmitter and becomes a pacer: `send(_:)` sets a goal, an internal ticker walks the
emitted pose there through the limiter. In ReachyUI a `TeleopDriver` model owns the target for both teleop screens,
maps joystick deflection onto head pose through a pure `JoystickMapping`, and integrates body yaw while the knob sits
in a rotation zone.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, swift-testing (`@Test`/`#expect`), SwiftPM + Tuist, Prefire
snapshots.

**Spec:** `docs/superpowers/specs/2026-08-05-joystick-smoothing-and-body-rotation-design.md`

## Global Constraints

- Every command runs through mise: `./bin/mise run build`, `./bin/mise run test`, `./bin/mise run lint`. Never call
  `swift build`, `swiftlint` or `xcodebuild` bare.
- Run one SwiftPM process at a time — a second invocation blocks on the `.build` lock. Check
  `pgrep -f 'swift-build|swift-test'` before diagnosing a hang.
- `./bin/mise run test:filter <TypeName>` matches **type** names, not `@Suite` display names.
- Deployment floor: iOS 18 / macOS 15. `.sensoryFeedback` (iOS 17 / macOS 14) is therefore available with no `#if`.
- **No `#Preview` outside `Sources/ReachyUI/Previews`** — that directory is excluded from the SwiftPM target, and a
  `#Preview` anywhere else breaks `build`, `test` and CI with "plugin for module 'PreviewsMacros' not found".
- Safety limits stay in the daemon (project rule 2). Nothing in this work clamps a _position_ the daemon would clamp;
  it bounds only the _speed of approach_ to a target the caller was already allowed to request.
- Conventional commits, enforced by the commit-msg hook. The pre-commit hook stages **every** modified `.swift` and
  `.md` in the worktree, not only what you `git add` — so commit with a clean tree around the task at hand. PNGs are
  never staged for you.
- Comments: only non-obvious "why", one terse line. No narration of what the code plainly says.

---

### Task 1: `TargetSlewLimiter`

The pure value that all smoothing rests on. No clock, no actor, no I/O.

**Files:**

- Create: `Sources/ReachyKit/Transport/TargetSlewLimiter.swift`
- Test: `Tests/ReachyKitTests/TargetSlewLimiterTests.swift`

**Interfaces:**

- Consumes: `SetTargetClient.Target` (exists, 9 `Double` fields: `x y z roll pitch yaw bodyYaw antennaLeft
  antennaRight`).
- Produces:
  - `public struct TargetSlewLimiter: Sendable`
  - `public var tau: Duration`, `public var headAngularRate: Double`, `public var bodyYawRate: Double`,
    `public var antennaRate: Double`, `public var translationRate: Double` (rates in units per second)
  - `public func next(current: SetTargetClient.Target, goal: SetTargetClient.Target, dt: Duration) -> SetTargetClient.Target`
  - `public func hasConverged(_ a: SetTargetClient.Target, to b: SetTargetClient.Target) -> Bool`
  - `static let axes: [(WritableKeyPath<SetTargetClient.Target, Double>, KeyPath<TargetSlewLimiter, Double>)]`
    (internal — the test reads it)

- [ ] **Step 1: Write the failing tests**

Create `Tests/ReachyKitTests/TargetSlewLimiterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./bin/mise run test:filter TargetSlewLimiterTests`
Expected: FAIL — "cannot find 'TargetSlewLimiter' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/ReachyKit/Transport/TargetSlewLimiter.swift`:

```swift
import Foundation

/// Bounds how fast an emitted target may walk toward its goal.
///
/// A plain rate limit stretches a step out in time but leaves velocity
/// discontinuous at both ends, which still reads as a jerk. The exponential term
/// takes over as the error shrinks, so the movement decelerates into the goal.
///
/// Safety limits stay in the daemon (project rule 2): this bounds the speed of
/// approach, never the target itself.
public struct TargetSlewLimiter: Sendable {
    /// Time constant of the exponential approach.
    public var tau: Duration
    /// Radians per second.
    public var headAngularRate: Double
    public var bodyYawRate: Double
    public var antennaRate: Double
    /// Meters per second.
    public var translationRate: Double

    public init(
        tau: Duration = .milliseconds(100),
        headAngularRate: Double = 90 * .pi / 180,
        bodyYawRate: Double = 120 * .pi / 180,
        antennaRate: Double = 240 * .pi / 180,
        translationRate: Double = 0.05
    ) {
        self.tau = tau
        self.headAngularRate = headAngularRate
        self.bodyYawRate = bodyYawRate
        self.antennaRate = antennaRate
        self.translationRate = translationRate
    }

    static let axes: [(WritableKeyPath<SetTargetClient.Target, Double>, KeyPath<TargetSlewLimiter, Double>)] = [
        (\.x, \.translationRate),
        (\.y, \.translationRate),
        (\.z, \.translationRate),
        (\.roll, \.headAngularRate),
        (\.pitch, \.headAngularRate),
        (\.yaw, \.headAngularRate),
        (\.bodyYaw, \.bodyYawRate),
        (\.antennaLeft, \.antennaRate),
        (\.antennaRight, \.antennaRate),
    ]

    private static let epsilon = 1e-5

    public func next(
        current: SetTargetClient.Target,
        goal: SetTargetClient.Target,
        dt: Duration
    ) -> SetTargetClient.Target {
        let seconds = dt.inSeconds
        guard seconds > 0 else { return current }
        let ease = 1 - exp(-seconds / tau.inSeconds)
        var next = current
        for (axis, rate) in Self.axes {
            let limit = self[keyPath: rate] * seconds
            let delta = (goal[keyPath: axis] - current[keyPath: axis]) * ease
            next[keyPath: axis] = current[keyPath: axis] + delta.clamped(to: -limit ... limit)
        }
        return next
    }

    public func hasConverged(_ a: SetTargetClient.Target, to b: SetTargetClient.Target) -> Bool {
        Self.axes.allSatisfy { abs(a[keyPath: $0.0] - b[keyPath: $0.0]) < Self.epsilon }
    }
}

extension Duration {
    var inSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
```

If the compiler rejects the `static let axes` array as non-`Sendable` (key-path Sendable conformance), change it to
`static var axes: [...] { [ … ] }` — a computed property has no global-state requirement. Do not reach for
`nonisolated(unsafe)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./bin/mise run test:filter TargetSlewLimiterTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Lint and commit**

```bash
./bin/mise run lint
git add Sources/ReachyKit/Transport/TargetSlewLimiter.swift Tests/ReachyKitTests/TargetSlewLimiterTests.swift
git commit -m "feat(kit): bound how fast a target may be approached"
```

---

### Task 2: `SetTargetClient` becomes a pacer

**Files:**

- Modify: `Sources/ReachyKit/Transport/SetTargetClient.swift`
- Modify: `Tests/ReachyKitTests/SetTargetClientTests.swift:22-50` (the `throttle` test is replaced)
- Modify: `Tests/ReachyKitTests/SimulatorIntegrationTests.swift:37` (parameter rename)

**Interfaces:**

- Consumes: `TargetSlewLimiter` from Task 1.
- Produces:
  - `public init(address: RobotAddress, tickInterval: Duration = .milliseconds(33), limiter: TargetSlewLimiter = TargetSlewLimiter(), session: URLSession = .shared) throws` — `minSendInterval` is **gone**.
  - `public func send(_ target: Target)` — now "aim for this", still called as `await client.send(target)` from
    outside the actor.

- [ ] **Step 1: Replace the throttle test with pacer tests**

In `Tests/ReachyKitTests/SetTargetClientTests.swift`, delete the `throttle` test (lines 22–50) and put these in its
place. Keep `wireFormat`, `waitUntil`, `ReceivedCounter` and `receiveLoop` exactly as they are.

```swift
    @Test("a step goal arrives as a run of frames, not one", .timeLimit(.minutes(1)))
    func pacing() async throws {
        let received = ReceivedCounter()
        let accepted = ReceivedCounter()
        let server = try LocalWebSocketServer { connection in
            accepted.increment()
            receiveLoop(connection, counter: received)
        }
        defer { server.stop() }
        let port = try await server.readyPort()

        let client = try SetTargetClient(
            address: RobotAddress(host: "127.0.0.1", port: Int(port)),
            tickInterval: .milliseconds(10)
        )
        await client.connect()
        await waitUntil(accepted.count >= 1)

        // Half a turn cannot be one frame: at the limiter's body ceiling it needs
        // more than a second, so the wire must carry the whole ramp.
        await client.send(.init(bodyYaw: .pi))
        await waitUntil(received.count >= 5)
        #expect(received.count >= 5)
        await client.disconnect()
    }

    @Test("the pacer goes quiet once it reaches the goal", .timeLimit(.minutes(1)))
    func quiescence() async throws {
        let received = ReceivedCounter()
        let accepted = ReceivedCounter()
        let server = try LocalWebSocketServer { connection in
            accepted.increment()
            receiveLoop(connection, counter: received)
        }
        defer { server.stop() }
        let port = try await server.readyPort()

        let client = try SetTargetClient(
            address: RobotAddress(host: "127.0.0.1", port: Int(port)),
            tickInterval: .milliseconds(10)
        )
        await client.connect()
        await waitUntil(accepted.count >= 1)

        await client.send(.init(yaw: 0.01))
        await waitUntil(received.count >= 1)
        // Absence of traffic can only be observed over a window — there is no
        // condition to poll for "nothing more will arrive". 300 ms is 30 ticks, so
        // a pacer that never stopped would be caught thirty times over.
        try await Task.sleep(for: .milliseconds(300))
        let settled = received.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(received.count == settled)
        await client.disconnect()
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `./bin/mise run test:filter SetTargetClientTests`
Expected: FAIL — the compiler rejects `tickInterval:`, which does not exist yet.

- [ ] **Step 3: Rewrite the client**

In `Sources/ReachyKit/Transport/SetTargetClient.swift`, replace the doc comment, the stored properties, `init`,
`connect`, `disconnect` and `send` as follows. `Target`, `lastServerError`, `record(serverError:)` and `encode` are
untouched.

```swift
/// Live teleop: streams `FullBodyTarget` frames to `ws://…/api/move/ws/set_target`.
///
/// `send(_:)` sets a *goal*; a ticker walks the emitted pose toward it under
/// `TargetSlewLimiter` and stops transmitting once it arrives. Every writer in the
/// app funnels through here, so none of them — a joystick release, a slider jump,
/// "Reset to neutral" — can put a step on the wire.
///
/// The daemon clamps all safety limits server-side and ignores targets while a
/// recorded move is running. The server's error replies are drained and kept in
/// `lastServerError`.
public actor SetTargetClient {
```

```swift
    private let url: URL
    private let session: URLSession
    private let tickInterval: Duration
    private let limiter: TargetSlewLimiter
    private var socket: URLSessionWebSocketTask?
    private var drainTask: Task<Void, Never>?
    private var pacerTask: Task<Void, Never>?
    private var goal = Target()
    private var emitted = Target()

    public init(
        address: RobotAddress,
        tickInterval: Duration = .milliseconds(33),
        limiter: TargetSlewLimiter = TargetSlewLimiter(),
        session: URLSession = .shared
    ) throws {
        guard let url = address.webSocketURL(path: Self.path) else {
            throw ReachyKitError.invalidAddress(address)
        }
        self.url = url
        self.session = session
        self.tickInterval = tickInterval
        self.limiter = limiter
    }

    public func connect() {
        guard socket == nil else { return }
        let socket = session.webSocketTask(with: url)
        socket.resume()
        self.socket = socket
        drainTask = Task { [weak self] in
            while let self, let socket = await self.socket {
                guard let message = try? await socket.receive() else { break }
                if case let .string(text) = message {
                    await record(serverError: text)
                }
            }
        }
        let interval = tickInterval
        pacerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.tick()
            }
        }
    }

    public func disconnect() {
        pacerTask?.cancel()
        pacerTask = nil
        drainTask?.cancel()
        drainTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Aims at `target`. Nothing goes out here — the pacer decides when and how
    /// fast, which is what makes every command path smooth by construction.
    public func send(_ target: Target) {
        goal = target
    }

    private func tick() async {
        guard let socket, emitted != goal else { return }
        let next = limiter.next(current: emitted, goal: goal, dt: tickInterval)
        emitted = limiter.hasConverged(next, to: goal) ? goal : next
        guard let text = String(bytes: Self.encode(emitted), encoding: .utf8) else { return }
        try? await socket.send(.string(text))
    }
```

- [ ] **Step 4: Fix the simulator integration test's parameter name**

In `Tests/ReachyKitTests/SimulatorIntegrationTests.swift:37`, change
`SetTargetClient(address: address, minSendInterval: .milliseconds(10))` to
`SetTargetClient(address: address, tickInterval: .milliseconds(10))`. Nothing else in that test changes — `send` in a
loop still works, it now just re-states the same goal.

- [ ] **Step 5: Fix the two UI call sites so the package compiles**

`Sources/ReachyUI/CameraViewport.swift:70` and `Sources/ReachyUI/ControllerScreen.swift:131` construct
`SetTargetClient(address:)` with no other argument — they compile unchanged. Verify, don't assume:

Run: `./bin/mise run build`
Expected: build succeeds.

- [ ] **Step 6: Run the tests**

Run: `./bin/mise run test:filter SetTargetClientTests`
Expected: PASS, 3 tests.

- [ ] **Step 7: Lint and commit**

```bash
./bin/mise run lint
git add Sources/ReachyKit/Transport/SetTargetClient.swift Tests/ReachyKitTests/SetTargetClientTests.swift Tests/ReachyKitTests/SimulatorIntegrationTests.swift
git commit -m "feat(kit): pace teleop targets instead of dropping them"
```

---

### Task 3: `JoystickDeflection` and `JoystickMapping`

The joystick's semantics as a pure function, testable without a view.

**Files:**

- Create: `Sources/ReachyUI/JoystickMapping.swift`
- Test: `Tests/ReachyUITests/JoystickMappingTests.swift`

**Interfaces:**

- Consumes: `TargetSlewLimiter` from Task 1 (the invariant test reads its `bodyYawRate`).
- Produces:
  - `struct JoystickDeflection: Equatable, Sendable { var x: Double; var y: Double; static let zero }`
  - `struct JoystickMapping: Equatable, Sendable` with `rotationThreshold = 0.7`, `headAngle = 40°`,
    `maxBodyYawRate = 60°/s`, and `headYaw(_:) -> Double`, `headPitch(_:) -> Double`, `bodyYawRate(_:) -> Double`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ReachyUITests/JoystickMappingTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `./bin/mise run test:filter JoystickMappingTests`
Expected: FAIL — "cannot find 'JoystickMapping' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/ReachyUI/JoystickMapping.swift`:

```swift
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
```

Note: `Sources/ReachyUI/JoystickPad.swift:44-48` already declares `extension CGFloat { clamped(to:) }`. `CGFloat` and
`Double` are distinct types, so both can coexist — but the CGFloat one becomes unused in Task 5 and is deleted there.

- [ ] **Step 4: Run to verify they pass**

Run: `./bin/mise run test:filter JoystickMappingTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Lint and commit**

```bash
./bin/mise run lint
git add Sources/ReachyUI/JoystickMapping.swift Tests/ReachyUITests/JoystickMappingTests.swift
git commit -m "feat(ui): map the joystick's outer travel onto body rotation"
```

---

### Task 4: `TeleopDriver`

**Files:**

- Create: `Sources/ReachyUI/TeleopDriver.swift`
- Test: `Tests/ReachyUITests/TeleopDriverTests.swift`

**Interfaces:**

- Consumes: `SetTargetClient` (Task 2), `JoystickMapping` / `JoystickDeflection` (Task 3).
- Produces:
  - `@MainActor @Observable final class TeleopDriver`
  - `init(target: SetTargetClient.Target = SetTargetClient.Target(), mapping: JoystickMapping = JoystickMapping())`
  - `var target: SetTargetClient.Target` (writable — sliders bind to it; every write pushes)
  - `let mapping: JoystickMapping`, `private(set) var bodyYawRate: Double`
  - `func start(address: RobotAddress) throws`, `func stop()`, `func apply(_ deflection: JoystickDeflection)`,
    `func reset()`, `func integrateRotation(seconds: Double)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ReachyUITests/TeleopDriverTests.swift`:

```swift
import ReachyKit
@testable import ReachyUI
import Testing

/// The rotation ticker is a real `Task`, but every test body below is synchronous:
/// with no suspension point the main actor never yields, so the ticker cannot
/// interleave with an assertion. `stop()` at the end keeps it from outliving the test.
@MainActor
@Suite("Teleop driver")
struct TeleopDriverTests {
    @Test("inside the head zone the joystick moves the head and nothing else")
    func headOnly() {
        let driver = TeleopDriver()
        driver.apply(.init(x: 0.5, y: -0.25))
        #expect(driver.target.yaw < 0)
        #expect(driver.target.pitch < 0)
        #expect(driver.bodyYawRate == 0)
        #expect(driver.target.bodyYaw == 0)
    }

    @Test("past the zone the head holds and the body starts turning")
    func rotationStarts() {
        let driver = TeleopDriver()
        driver.apply(.init(x: 1.0))
        #expect(abs(driver.target.yaw + driver.mapping.headAngle) < 1e-9)
        #expect(driver.bodyYawRate != 0)
        driver.stop()
    }

    @Test("integration accumulates and clamps at half a turn")
    func integrationClamps() {
        let driver = TeleopDriver()
        driver.apply(.init(x: -1.0))
        for _ in 0 ..< 400 {
            driver.integrateRotation(seconds: 0.02)
        }
        #expect(abs(driver.target.bodyYaw - .pi) < 1e-9)
        driver.stop()
    }

    /// The whole point of turning: letting go must not undo it.
    @Test("releasing returns the head and leaves the body where it turned to")
    func releaseKeepsBodyYaw() {
        let driver = TeleopDriver()
        driver.apply(.init(x: -1.0))
        for _ in 0 ..< 25 {
            driver.integrateRotation(seconds: 0.02)
        }
        let turned = driver.target.bodyYaw
        #expect(turned > 0)

        driver.apply(.zero)
        #expect(driver.target.yaw == 0)
        #expect(driver.bodyYawRate == 0)
        #expect(driver.target.bodyYaw == turned)

        driver.integrateRotation(seconds: 0.02)
        #expect(driver.target.bodyYaw == turned)
    }

    @Test("reset returns the body too")
    func reset() {
        let driver = TeleopDriver(target: .init(roll: 0.3, bodyYaw: 1.2))
        driver.reset()
        #expect(driver.target == SetTargetClient.Target())
        #expect(driver.bodyYawRate == 0)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./bin/mise run test:filter TeleopDriverTests`
Expected: FAIL — "cannot find 'TeleopDriver' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/ReachyUI/TeleopDriver.swift`:

```swift
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
        guard rate != 0 else { return stopRotation() }
        guard rotationTask == nil else { return }
        rotationTask = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                let now = ContinuousClock.now
                let elapsed = last.duration(to: now)
                last = now
                guard let self else { return }
                self.integrateRotation(seconds: elapsed.inSeconds)
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
```

`guard rate != 0 else { return stopRotation() }` returns `Void` from a `Void` function — valid Swift. If SwiftLint
objects, split it into an `if`.

- [ ] **Step 4: Run to verify they pass**

Run: `./bin/mise run test:filter TeleopDriverTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Lint and commit**

```bash
./bin/mise run lint
git add Sources/ReachyUI/TeleopDriver.swift Tests/ReachyUITests/TeleopDriverTests.swift
git commit -m "feat(ui): drive teleop from one model that can turn the body"
```

---

### Task 5: `JoystickPad` — deflection, zone arcs, haptics

**Files:**

- Modify: `Sources/ReachyUI/JoystickPad.swift` (full rewrite)
- Modify: `Sources/ReachyUI/CameraViewport.swift:57-61` (adapt to the new callback)
- Modify: `Sources/ReachyUI/ControllerScreen.swift:42-46` (adapt to the new callback)
- Modify: `Sources/ReachyUI/Previews/JoystickPadPreviews.swift` (adapt; the new preview comes in Task 7)

**Interfaces:**

- Consumes: `JoystickDeflection`, `JoystickMapping` (Task 3).
- Produces:
  - `init(mapping: JoystickMapping = JoystickMapping(), deflection: JoystickDeflection = .zero, onChange: @escaping (JoystickDeflection) -> Void)`
  - `enum JoystickRotationSide: Equatable { case left, right }`

The `deflection:` argument exists so a preview can capture the lit-arc state, which no snapshot can reach by
gesturing.

- [ ] **Step 1: Rewrite the pad**

Replace the whole of `Sources/ReachyUI/JoystickPad.swift`:

```swift
import SwiftUI

/// Which rotation zone the knob is in.
enum JoystickRotationSide: Equatable {
    case left, right
}

/// 2D touch pad emitting a normalized deflection; snaps back to centre on release.
///
/// Past `mapping.rotationThreshold` sideways the knob enters a rotation zone, which
/// the pad marks with a lit arc and a haptic tick. The pad itself only reports where
/// the knob is — turning that into head pose or body rotation is `TeleopDriver`'s job.
struct JoystickPad: View {
    var mapping: JoystickMapping
    var onChange: (JoystickDeflection) -> Void

    @State private var deflection: JoystickDeflection

    init(
        mapping: JoystickMapping = JoystickMapping(),
        deflection: JoystickDeflection = .zero,
        onChange: @escaping (JoystickDeflection) -> Void
    ) {
        self.mapping = mapping
        self.onChange = onChange
        _deflection = State(initialValue: deflection)
    }

    private var rotationSide: JoystickRotationSide? {
        guard abs(deflection.x) > mapping.rotationThreshold else { return nil }
        return deflection.x > 0 ? .right : .left
    }

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            ZStack {
                Circle()
                    .fill(.quaternary.opacity(0.3))
                Circle()
                    .strokeBorder(.tertiary, lineWidth: 1)
                zoneArc(.left)
                zoneArc(.right)
                Circle()
                    .fill(.tint)
                    .frame(width: 56, height: 56)
                    .offset(x: CGFloat(deflection.x) * radius, y: CGFloat(deflection.y) * radius)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(drag(radius: radius))
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact, trigger: rotationSide)
    }

    private func drag(radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                deflection = JoystickDeflection(
                    x: Double(value.translation.width / radius).clamped(to: -1 ... 1),
                    y: Double(value.translation.height / radius).clamped(to: -1 ... 1)
                )
                onChange(deflection)
            }
            .onEnded { _ in
                withAnimation(.snappy) { deflection = .zero }
                onChange(.zero)
            }
    }

    /// Where the body starts turning. Lit while the knob is inside it.
    private func zoneArc(_ side: JoystickRotationSide) -> some View {
        Circle()
            .trim(from: 0, to: 0.1)
            .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(side == .right ? -18 : 162))
            .foregroundStyle(rotationSide == side ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .padding(3)
    }
}
```

The `extension CGFloat { clamped(to:) }` at the bottom of the old file goes away — the `Double` version from
Task 3 replaces it. Confirm nothing else used it: `grep -rn "clamped(to:" Sources Tests`.

- [ ] **Step 2: Adapt the two call sites so the package compiles**

`Sources/ReachyUI/CameraViewport.swift`, in `joystick`:

```swift
JoystickPad { deflection in
    target.yaw = -deflection.x * headAngle
    target.pitch = deflection.y * headAngle
    push()
}
```

`Sources/ReachyUI/ControllerScreen.swift`, in the head section:

```swift
JoystickPad { deflection in
    target.yaw = -deflection.x * headAngle
    target.pitch = deflection.y * headAngle
    push()
}
```

These are temporary — Task 6 replaces both with the driver. They exist so this task compiles and commits on its own.

`Sources/ReachyUI/Previews/JoystickPadPreviews.swift`: change both `JoystickPad { _, _ in }` to
`JoystickPad { _ in }`.

- [ ] **Step 3: Build and run the whole suite**

Run: `./bin/mise run build && ./bin/mise run test`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Lint and commit**

```bash
./bin/mise run lint
git add Sources/ReachyUI/JoystickPad.swift Sources/ReachyUI/CameraViewport.swift Sources/ReachyUI/ControllerScreen.swift Sources/ReachyUI/Previews/JoystickPadPreviews.swift
git commit -m "feat(ui): show and feel the joystick's rotation zone"
```

---

### Task 6: Wire both screens to the driver

**Files:**

- Modify: `Sources/ReachyUI/CameraViewport.swift`
- Modify: `Sources/ReachyUI/ControllerScreen.swift`
- Modify: `Sources/ReachyUI/Previews/PreviewScenes.swift:96-105`
- Modify: `Sources/ReachyUI/Previews/ControllerScreenPreviews.swift`

**Interfaces:**

- Consumes: `TeleopDriver` (Task 4), `JoystickPad` (Task 5).
- Produces:
  - `CameraViewport.init(session: CameraSession, address: RobotAddress, driver: TeleopDriver = TeleopDriver())`
  - `ControllerScreen.init(session: RobotSession, address: RobotAddress, driver: TeleopDriver = TeleopDriver(), setupError: String? = nil)` — the `target:` parameter is replaced by `driver:`
  - `PreviewScene.controller(_ session: RobotSession, driver: TeleopDriver = TeleopDriver(), setupError: String? = nil)`

Follow `MovesScreen.init(session:model:)` (`Sources/ReachyUI/MovesScreen.swift:11-14`) exactly for the injection
shape: a defaulted argument plus `_driver = State(initialValue: driver)`. That form is already proven to compile in
the `Apps/` targets with a `@MainActor` model.

- [ ] **Step 1: Rewrite `CameraViewport`'s teleop**

Replace the `teleop`/`target`/`headAngle` properties, the `joystick` body, `connectTeleop()` and `push()`:

```swift
struct CameraViewport: View {
    let session: CameraSession
    let address: RobotAddress

    @State private var driver: TeleopDriver
    @Environment(\.reachyPreviewMode) private var previewMode

    init(session: CameraSession, address: RobotAddress, driver: TeleopDriver = TeleopDriver()) {
        self.session = session
        self.address = address
        _driver = State(initialValue: driver)
    }
```

```swift
    @ViewBuilder
    private var joystick: some View {
        if session.phase == .streaming {
            JoystickPad(mapping: driver.mapping) { driver.apply($0) }
                .frame(width: 140, height: 140)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()
        }
    }

    private func connectTeleop() {
        guard !previewMode else { return }
        try? driver.start(address: address)
    }
```

and `.onDisappear { driver.stop() }`. Update the type's doc comment: the joystick now drives head yaw/pitch **and**
turns the body when held sideways.

- [ ] **Step 2: Rewrite `ControllerScreen`**

```swift
    @State private var driver: TeleopDriver
    @State private var setupError: String?
    @Environment(\.reachyPreviewMode) private var previewMode

    init(
        session: RobotSession,
        address: RobotAddress,
        driver: TeleopDriver = TeleopDriver(),
        setupError: String? = nil
    ) {
        self.session = session
        self.address = address
        _driver = State(initialValue: driver)
        _setupError = State(initialValue: setupError)
    }

    // Comfortable UI ranges; hardware limits are clamped by the daemon anyway.
    private let fullTurn = 180.0 * .pi / 180
    private let antennaRange = 150.0 * .pi / 180
```

`headAngle` is deleted — it lives in `driver.mapping.headAngle` now. In `body`, add `@Bindable var driver = driver`
as the first line (the `MovesScreen` pattern) and rewrite the sections:

```swift
Section("Head — drag: yaw / pitch, hold sideways: turn the body") {
    JoystickPad(mapping: driver.mapping) { driver.apply($0) }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
}
Section("Head") {
    slider(
        "Roll",
        value: $driver.target.roll,
        range: -driver.mapping.headAngle ... driver.mapping.headAngle,
        format: .degrees
    )
    slider("Height", value: $driver.target.z, range: -0.03 ... 0.03, format: .millimeters)
}
Section("Body") {
    slider("Body yaw", value: $driver.target.bodyYaw, range: -fullTurn ... fullTurn, format: .degrees)
}
Section("Antennas") {
    slider(
        "Left",
        value: $driver.target.antennaLeft,
        range: -antennaRange ... antennaRange,
        format: .degrees
    )
    slider(
        "Right",
        value: $driver.target.antennaRight,
        range: -antennaRange ... antennaRange,
        format: .degrees
    )
}
Section {
    Button("Reset to neutral") { driver.reset() }
}
```

The `slider` helper loses its push-on-set wrapper, because writing through the binding mutates `driver.target`, whose
`didSet` pushes:

```swift
Slider(value: value, in: range)
```

`start()` and `onChange(of: session.isAwake)` become:

```swift
private func start() {
    guard !previewMode else { return }
    do {
        try driver.start(address: address)
    } catch {
        setupError = "\(error)"
    }
}
```

```swift
.onChange(of: session.isAwake) { _, awake in
    // Targets accumulated while asleep would be replayed as one move.
    if awake {
        driver.reset()
    }
}
.onDisappear { driver.stop() }
```

Delete the now-unused `client` state and the old `push()`.

- [ ] **Step 3: Update the preview scene helper**

`Sources/ReachyUI/Previews/PreviewScenes.swift`:

```swift
static func controller(
    _ session: RobotSession,
    driver: TeleopDriver = TeleopDriver(),
    setupError: String? = nil
) -> some View {
    NavigationHost {
        ControllerScreen(session: session, address: address, driver: driver, setupError: setupError)
    }
    .preview()
}
```

and in `ControllerScreenPreviews.swift` the "displaced" preview:

```swift
#Preview("Controller — displaced") {
    PreviewScene.controller(
        .preview(),
        driver: TeleopDriver(target: .init(z: 0.02, roll: 0.35, bodyYaw: 1.2, antennaLeft: -1.1, antennaRight: 0.9))
    )
}
```

- [ ] **Step 4: Build both build systems**

Run: `./bin/mise run build && ./bin/mise run test`
Expected: pass.

Run: `./bin/mise run build:app`
Expected: pass. This is the one that compiles `Previews/`; a mistake in Step 3 shows up only here.

- [ ] **Step 5: Lint and commit**

```bash
./bin/mise run lint
git add Sources/ReachyUI/CameraViewport.swift Sources/ReachyUI/ControllerScreen.swift Sources/ReachyUI/Previews/PreviewScenes.swift Sources/ReachyUI/Previews/ControllerScreenPreviews.swift
git commit -m "refactor(ui): give both teleop screens one driver"
```

---

### Task 7: Previews and snapshot references

**Files:**

- Modify: `Sources/ReachyUI/Previews/JoystickPadPreviews.swift`
- Modify: `Apps/ReachyUISnapshotTests/__Snapshots__/JoystickPadPreviewsTests.generated/*.png`
- Modify: `Apps/ReachyUISnapshotTests/__Snapshots__/ControllerScreenPreviewsTests.generated/*.png`

Project rule 8: a state a user can land in gets a preview and a recorded reference. The lit-arc state cannot be
reached by a snapshot gesturing, which is what the `deflection:` seam from Task 5 is for.

- [ ] **Step 1: Add the rotation preview**

Append to `Sources/ReachyUI/Previews/JoystickPadPreviews.swift`:

```swift
// The lit arc has no gesture behind it in a snapshot, so the deflection is injected.
#Preview("Joystick — turning", traits: .sizeThatFitsLayout) {
    JoystickPad(deflection: .init(x: 0.95, y: -0.2)) { _ in }
        .padding()
}
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `./bin/mise run project`
Expected: succeeds. Prefire reads previews off the filesystem but Xcode compiles the file list Tuist baked in — a
bare `xcodebuild` would fail with "cannot find … in scope".

- [ ] **Step 3: See exactly which references moved before overwriting any**

Run: `./bin/mise run test:snapshots`
Expected: FAIL, naming the references that changed. Expect the two `JoystickPad` ones (the arcs are new) and the five
`ControllerScreen` ones per device (the pad sits inside that screen). `Joystick — turning` is _created_, not compared —
Prefire generates `record: .missing`.

Write down the list. If a reference moves that this change cannot explain — a screen with no joystick on it — stop and
read the CLAUDE.md note on spinner-bearing previews before re-recording.

- [ ] **Step 4: Re-record and inspect**

```bash
./bin/mise run test:snapshots:record
git status --porcelain 'Apps/ReachyUISnapshotTests/**/*.png'
```

Open one Controller reference and confirm the only difference is the two arcs on the pad.

- [ ] **Step 5: Verify the recording is stable, then commit**

Run: `./bin/mise run test:snapshots`
Expected: PASS.

```bash
git add Sources/ReachyUI/Previews/JoystickPadPreviews.swift
git add Apps/ReachyUISnapshotTests/__Snapshots__
git commit -m "test(ui): record the joystick's rotation zone"
```

The PNGs need that explicit `git add` — they are Git LFS, and the pre-commit hook stages only `.swift` and `.md`.

---

### Task 8: Tune on the robot

Constants chosen at a desk are guesses. A green suite cannot tell whether a return still reads as a snap, and the
simulator cannot either.

**Files:**

- Possibly modify: `Sources/ReachyKit/Transport/TargetSlewLimiter.swift` (the rate defaults)
- Possibly modify: `Sources/ReachyUI/JoystickMapping.swift` (`maxBodyYawRate`, `rotationThreshold`)

- [ ] **Step 1: Build and run on the physical robot**

Run: `./bin/mise run build:app`, then deploy to the device and connect to the real Reachy Mini.

- [ ] **Step 2: Check each behaviour by hand**

- Release from full deflection: the head should ease back, not snap. Measured against the current constants it takes
  roughly 0.65 s to come within half a degree of neutral.
- Drag a slider on Controller from one end to the other: the robot should follow smoothly.
- "Reset to neutral" with the body turned 180°: the robot should unwind, not spin.
- Hold the joystick fully sideways: the body should start turning from a standstill and reach a steady speed.
- Confirm the direction: pushing right must turn the robot to its right. If it does not, flip the sign in
  `JoystickMapping.bodyYawRate` and say so in its doc comment — the sign is not documented anywhere in the codebase.

- [ ] **Step 3: Adjust and re-verify**

If constants change, re-run `./bin/mise run test` — `returnFromFullDeflection` and `staysUnderTheCeiling` are the two
that bound them, and both should still pass. If `staysUnderTheCeiling` fails, the joystick rate was raised above the
limiter's body ceiling; raise the ceiling too.

- [ ] **Step 4: Commit any tuning**

```bash
./bin/mise run lint
git add -u
git commit -m "fix(ui): tune the teleop rates against the robot"
```

---

## Notes for the implementer

- `SetTargetClient.send` stays `await`-ed at every call site even though it is no longer `async` — actor isolation
  supplies that. Do not "fix" the call sites.
- The rotation ticker in `TeleopDriver` captures `self` weakly and reads `Self.tick` as a static, so the loop needs no
  actor hop to read its own interval and dies on its own once the driver goes away.
- Do not add a `Task.sleep` before an assertion in any new test. The one place a wait is unavoidable — proving the
  pacer went _quiet_ — carries a comment explaining why no condition can be polled there.
- `Apps/DerivedData` is Xcode's and is several gigabytes; `mise run clean` does not touch it. Never pass a bare `.` to
  swiftlint or swiftformat.
