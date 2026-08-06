import SwiftUI

/// Text roles, each one a semantic `Font`. Nothing here names a point size, so
/// Dynamic Type costs nothing to support.
public enum Typography {
    public static let screenTitle: Font = .title2
    public static let rowTitle: Font = .headline
    /// The same title on a strip 56 pt tall that carries a caption under it.
    public static let rowTitleCompact: Font = .subheadline
    /// And on a widget tile, which is narrower again — a caption doing a title's job.
    public static let tileTitle: Font = .caption
    public static let detail: Font = .callout
    public static let status: Font = .caption
    /// The same caption where a widget tile has no room for `.caption`.
    public static let statusCompact: Font = .caption2
    public static let console: Font = .body.monospaced()
    public static let consoleLine: Font = .caption.monospaced()
}

/// A glyph sized off its container rather than off the text scale.
///
/// `AppArtworkTile` draws an emoji or an SF Symbol *as artwork*, which is the one
/// place `.font(.system(size:))` is right: the glyph has to track the tile, not
/// the reader's text size. These are the two ratios it uses.
public enum IconRatio {
    public static let emoji: CGFloat = 0.5
    public static let symbol: CGFloat = 0.42
}
