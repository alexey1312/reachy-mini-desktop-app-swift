import SwiftUI

/// The three animations the app actually runs, named.
///
/// No reduce-motion resolver sits behind these — that is deliberately out of
/// scope, so a call site must not read one into the names.
public enum Motion {
    /// The dock arriving from under the tab bar and leaving the same way.
    public static let dock: Animation = .snappy(duration: 0.28)
    /// A control returning to rest when the finger lifts.
    public static let springBack: Animation = .snappy
    public static let stateChange: Animation = .default
}
