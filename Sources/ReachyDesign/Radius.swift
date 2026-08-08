import SwiftUI

/// Corner radii, and the one constructor that applies them.
///
/// `rect(_:)` is the only rounded rectangle this module hands out, which is what
/// makes "every rounded corner here is `.continuous`" hold by construction rather
/// than by review — SwiftUI's own initialiser defaults to `.circular`.
public enum Radius {
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 10
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    /// The dock's top edge — Telegram's `containerNode.cornerRadius`, and what
    /// makes the strip read as a window under the app rather than as its toolbar.
    public static let window: CGFloat = 25

    /// An app tile's corner scales with the tile, so a 30 pt dock tile and a 52 pt
    /// store tile read as the same object at two sizes.
    public static func tile(side: CGFloat) -> CGFloat {
        side / 4.5
    }

    public static func rect(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// A rectangle with the two corners on one side squared off — the shape something
    /// flush with a screen edge takes, so it reads as hanging off the side rather than
    /// as a shrunken window. `nil` is flush with nothing and rounds all four.
    ///
    /// One shape type across both, deliberately: the floating viewport morphs between
    /// them on a single SwiftUI identity, and only one type can interpolate into
    /// itself. Returning a `RoundedRectangle` for the `nil` case would put an identity
    /// boundary in the middle of the animation and take the morph away again.
    public static func flush(to edge: HorizontalEdge?, _ radius: CGFloat) -> UnevenRoundedRectangle {
        let leading = edge == .leading ? 0 : radius
        let trailing = edge == .trailing ? 0 : radius
        return UnevenRoundedRectangle(
            topLeadingRadius: leading,
            bottomLeadingRadius: leading,
            bottomTrailingRadius: trailing,
            topTrailingRadius: trailing,
            style: .continuous
        )
    }
}
