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
    /// The live view floating over the interface — wide enough to read what the
    /// robot is doing, narrow enough to leave a list legible beside it.
    public static let floatingViewport = CGSize(width: 160, height: 112)
    /// What that window leaves at the edge once it is switched off. 44 pt across
    /// because the tab is the only way back and nothing else can be aimed at.
    public static let viewportTab = CGSize(width: 44, height: 72)
    /// Room for the floating tab bar, for anything drawn *over* a `TabView`.
    ///
    /// The bar insets the safe area of each **tab's content** and reports none of
    /// it to an overlay on the `TabView` itself, which is a `GeometryReader` that
    /// sees the home indicator and nothing else. Measured off `Root — unreachable`,
    /// where the first version of the floating viewport landed squarely on the
    /// Apps and Settings labels.
    public static let tabBarAllowance: CGFloat = 56
    /// A `Form` left to itself fills a 1024 pt iPad and reads as broken.
    public static let readableForm: CGFloat = 560
}
