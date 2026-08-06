import SwiftUI

/// Neighbouring surfaces that should read as one sheet of glass rather than as a
/// row of separate panes.
///
/// It only means anything from iOS 26 / macOS 26, where `GlassEffectContainer`
/// merges the glass of everything inside it and lets two controls flow together as
/// they approach. Below that floor it renders its content untouched — so a call
/// site groups its chrome once and never forks on the version.
///
/// `spacing` is how close two surfaces come before they merge, not a layout gap:
/// the stack inside keeps its own.
public struct ReachySurfaceGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = Space.md, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
