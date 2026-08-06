import CoreGraphics

/// Sizes fixed by what they represent rather than by the text inside them.
///
/// These are what clip at AX5, which is why `@ScaledMetric` belongs on the
/// component that reads one and never on the constant: at the default text size
/// the multiplier is 1, so adopting it moves no reference image.
public enum Metrics {
    /// Telegram's `minimizedNavigationHeight` — the running-app strip.
    public static let dockStrip: CGFloat = 56
    public static let joystickKnob: CGFloat = 56
    /// A store row's artwork, and the smaller tile the dock and the widget draw.
    public static let artwork: CGFloat = 52
    public static let artworkCompact: CGFloat = 30
    /// The gutter that keeps a stepper's symbols on one optical axis.
    public static let stepperIconColumn: CGFloat = 18
    /// A `Form` left to itself fills a 1024 pt iPad and reads as broken.
    public static let readableForm: CGFloat = 560
}
