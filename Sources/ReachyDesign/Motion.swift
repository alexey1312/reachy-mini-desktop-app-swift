import SwiftUI

/// The animations the app actually runs, named.
///
/// The three constants resolve nothing: each is a one-shot response to something
/// the user did or something that changed, and Reduce Motion is not about those.
/// `waiting(reduceMotion:)` is the exception and the only one — see below.
public enum Motion {
    /// The dock arriving from under the tab bar and leaving the same way.
    public static let dock: Animation = .snappy(duration: 0.28)
    /// A control returning to rest when the finger lifts.
    public static let springBack: Animation = .snappy
    public static let stateChange: Animation = .default

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
