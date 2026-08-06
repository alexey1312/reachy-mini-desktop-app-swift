import CoreGraphics

/// The layout rhythm, on a 4-point grid.
///
/// Two rules govern its use, and the second is what keeps the reference images
/// honest:
///
/// 1. The rhythm of a layout — gaps between rows, sections and stacked controls —
///    comes from here. Optical adjustments *inside* one component (the dock's
///    `VStack(spacing: 1)`, the 3 pt inset on the joystick's arc) stay literals
///    with a note: a grid that swallowed the optics is worse than no grid.
/// 2. A site adopts a token where the value already matches (4, 8, 12, 16). The
///    odd ones (1, 3, 5, 6, 10, 14) are re-judged only inside a PR that redraws
///    that component anyway — otherwise one `10 → 12` moves every reference image
///    it touches without a single design reason behind it.
public enum Space {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}
