# Joystick smoothing and body rotation

## Problem

Two complaints from the camera viewport, one behavioural and one missing feature.

**The head snaps back.** `JoystickPad.onEnded` (`Sources/ReachyUI/JoystickPad.swift:34`) animates the knob
back to centre with `withAnimation(.snappy)` and, in the same breath, hands the robot a single
`onChange(0, 0)`. The animation is SwiftUI's alone; the daemon receives one frame saying "neutral" and drives
there at whatever speed it can. Every release is a step input. The same holds for the "Reset to neutral"
button and for any large slider drag on `ControllerScreen` — a body yaw at 180° reset in one frame is the
worst case in the app.

**The body does not turn.** Horizontal deflection maps to head yaw only. `target_body_yaw` reaches the wire
(`SetTargetClient.encode`) but nothing in the camera viewport ever writes it, so the robot can look sideways
and never face sideways.

A third defect surfaced while reading the code and is fixed on the way past. `SetTargetClient.send`
(`Sources/ReachyKit/Transport/SetTargetClient.swift:80`) drops the _incoming_ frame when the previous send
was under 33 ms ago. The doc comment claims "latest wins"; the code means first-wins-per-window. Worse, a
finger held still emits no `DragGesture.onChanged` at all, so the stream simply stops — which is also why
velocity-style control cannot be built on the gesture alone.

## Goals

- Releasing the joystick returns the head to neutral smoothly, not instantly.
- No command path can produce an abrupt movement — joysticks, sliders and Reset all pass the same limiter.
- Pushing the joystick past 70% of its travel sideways turns the whole robot, at a speed that grows from
  zero at the zone boundary. Releasing leaves the body where it turned to.
- The rotation zone is discoverable: visible arcs plus a haptic tick on entry.

Not in scope: pitch/vertical behaviour, the 3D viewport, gamepad or keyboard control, and any client-side
notion of a safety limit. Motion limits stay in the daemon (project rule 2); this work bounds only how fast
the client walks toward a target it was already entitled to request.

## Design

### `TargetSlewLimiter` (ReachyKit)

A pure value type, no actor and no clock of its own:

```swift
public struct TargetSlewLimiter: Sendable {
    public func next(
        current: SetTargetClient.Target,
        goal: SetTargetClient.Target,
        dt: Duration
    ) -> SetTargetClient.Target
}
```

Per axis:

```
step     = (goal - current) * (1 - exp(-dt / tau))
current += clamp(step, -maxRate * dt ... maxRate * dt)
```

For a large error the clamp binds and the axis travels at constant speed; as the error shrinks the
exponential takes over and the approach decelerates, so velocity is continuous at the end of the move. That
soft landing is what removes the perceived jerk — a pure rate limit slows the snap down without removing the
discontinuity at either end of it.

Starting constants, `tau = 0.10 s` and per-axis ceilings:

| Axis                   | Ceiling  |
| ---------------------- | -------- |
| Head roll/pitch/yaw    | 90°/s    |
| Body yaw               | 120°/s   |
| Antennas               | 240°/s   |
| Head translation x/y/z | 0.05 m/s |

From full deflection (40°) the head therefore reaches neutral in roughly 0.45 s. These are a first
approximation to be tuned against the physical robot; the simulator says nothing useful about how a movement
feels.

### `SetTargetClient` becomes a pacer

The actor gains a goal, an emitted pose and a ticker. `send(_:)` changes meaning from "transmit this" to
"aim for this" and stops being throttled at all. A task started with the socket ticks every 33 ms, advances
`emitted` toward `goal` through the limiter, and transmits while the two differ; once they converge to within
an epsilon it emits one exact final frame and goes quiet rather than spamming an idle robot. `disconnect()`
stops the ticker.

This is where "no abrupt movement anywhere" is actually enforced: every writer in the app — both joysticks,
every slider, the Reset button — goes through this one actor, so none of them can emit a step.

### `TeleopDriver` (ReachyUI)

A `@MainActor @Observable` model, per the rule in `Sources/ReachyUI/AGENTS.md` that screen logic lives beside
the view rather than in it. It owns the `Target` that `CameraViewport` and `ControllerScreen` currently each
keep in their own `@State`, which also retires the `headAngle` constant duplicated between them.

It holds the joystick's current deflection and, while that deflection sits inside a rotation zone, runs a
50 Hz tick doing `bodyYaw += rate * dt`, clamped to ±180°, pushing the updated goal to the client. The tick
runs only while a rotation is active — a centred or released joystick starts no timer.

Integration lives here rather than in the actor because `ControllerScreen`'s "Body yaw" slider is bound to
the same target. Were the angle to drift inside `SetTargetClient`, the slider would silently disagree with
the robot; owned by the driver, it tracks the rotation live.

### `JoystickMapping` (ReachyUI)

A pure function from deflection to intent, so the semantics are testable without a view:

| Zone          | Head yaw           | Body                                     |
| ------------- | ------------------ | ---------------------------------------- |
| `\|x\| ≤ 0.7` | `-(x / 0.7) · 40°` | still                                    |
| `\|x\| > 0.7` | held at ±40°       | `-sign(x) · (\|x\| - 0.7) / 0.3 · 60°/s` |

Vertical deflection keeps its present meaning, `pitch = y · 40°`. Rotation speed grows from zero at the
boundary, so crossing into the zone cannot itself produce a jolt. 60°/s is a full half-turn in three seconds.

**Invariant:** the joystick's maximum rotation speed must stay strictly below the limiter's body-yaw ceiling
(60 < 120). If the integrator outruns the limiter, the emitted pose falls permanently behind the goal and
the body turns at the limiter's speed rather than the one the finger asked for. A test asserts the ordering
rather than a comment stating it.

The sign of `bodyYaw` is not pinned down anywhere in the codebase and is verified on hardware, not guessed.

### `JoystickPad`

The callback changes from `(x, y)` to a `Deflection` value, because the view's own rendering now depends on
whether the deflection is inside a zone, not just on where it is.

Two arcs sit at the left and right edge of the circle, drawn in a muted tertiary style at rest. The arc the
finger has entered fills with the tint while rotation is active. Entry into a zone triggers
`.sensoryFeedback(.impact, trigger:)`, which exists from iOS 17 / macOS 14 — comfortably under this project's
iOS 18 / macOS 15 floor, so it needs no `#if` and is inert on macOS.

## Testing

The two pieces carrying the logic are values, and both are tested directly, with no socket and no sleeping
— project rule 7 is satisfied by construction here rather than by polling.

`TargetSlewLimiter`: a 180° error never advances more than `maxRate · dt` in one step; iterating converges
monotonically to the goal without overshoot; `dt = 0` is a no-op; every axis is covered, so a newly added
field cannot silently skip the limiter.

`JoystickMapping`: head yaw is linear to the boundary and saturates past it; body rate is exactly zero at the
boundary and reaches its maximum at full deflection; signs are symmetric; the maximum rate is below the
limiter's body ceiling.

`TeleopDriver`: integration clamps at ±180° and stops when the deflection leaves the zone.

`SetTargetClient` keeps its existing coverage; the ticker is exercised through the injected clock interval
rather than by waiting on wall time.

## Previews and snapshots

Project rule 8. `JoystickPad` gains a third preview for the rotation-active state, and its two existing
references change because the arcs alter the drawing. `mise run test:snapshots` runs first to see exactly
which references moved — `record` overwrites blind — and the PNGs are staged by hand, since no hook stages
them.

## Delivery

The work ends on the physical robot, not on a green suite: the constants above are guesses until someone
feels them, and a passing test cannot tell whether a return still reads as a snap.
