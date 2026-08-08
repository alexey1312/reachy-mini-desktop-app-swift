import SwiftUI

/// The animations the app actually runs, named.
///
/// Everything but `waiting(reduceMotion:)` resolves nothing: each is a one-shot
/// response to something the user did or something that changed, and Reduce Motion
/// is not about those. That one is the exception and the only one — see below.
public enum Motion {
    /// The dock arriving from under the tab bar and leaving the same way.
    public static let dock: Animation = .snappy(duration: 0.28)
    public static let stateChange: Animation = .default

    /// The floating window being drawn into its edge, and springing back out — and the
    /// one animation here that carries the gesture that started it.
    ///
    /// A spring rather than a curve, because the point is that a thrown window keeps
    /// going: `.snappy` restarts from a standstill however hard it was flicked, which
    /// is what made the old release read as a cut rather than as a throw.
    /// `.interpolatingSpring` is the only form that takes an initial velocity at all.
    ///
    /// **`velocity` is normalised, not points per second.** A spring animates a unit
    /// interval, so the caller divides its speed by the distance it has to cover —
    /// `FloatingViewport.release` is the worked example. Handing it raw points per
    /// second overshoots by whatever that distance happens to be.
    ///
    /// The ceiling is what keeps a hard flick from hurling the window far past its
    /// corner and hauling it back; `bounce` is the one number here to tune on a device
    /// rather than reason about.
    public static func absorb(velocity: CGFloat) -> Animation {
        .interpolatingSpring(duration: 0.32, bounce: 0.22, initialVelocity: min(abs(velocity), 12))
    }

    /// The picture leaving the floating window ahead of the window itself, so what gets
    /// squashed into the edge is an empty surface rather than a shrinking 3D scene.
    ///
    /// Shorter than `absorb` on purpose — roughly its first third — and that is the
    /// whole mechanism: it is scoped to the opacity with `animation(_:value:)` so the
    /// geometry keeps the spring while the content does not.
    public static let absorbContent: Animation = .easeOut(duration: 0.12)

    /// An indicator turning for as long as the app is waiting on something, and
    /// `nil` when the reader asked for less movement.
    ///
    /// This is the app's only animation that repeats without end, which is what
    /// makes it the only one Reduce Motion has an opinion about. The flag is a
    /// parameter rather than something read here: this module depends on SwiftUI
    /// for its types and on nothing for its decisions, so the environment is the
    /// caller's to read (`\.accessibilityReduceMotion`).
    ///
    /// A `nil` return means "do not animate", which is exactly what `withAnimation`
    /// and the `animation(_:value:)` modifier already take — no call site needs a
    /// branch of its own. What it does **not** mean is "show nothing": a caller
    /// that spins under this must still render a distinguishable resting state,
    /// or the reader loses the information along with the movement.
    public static func waiting(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false)
    }
}
