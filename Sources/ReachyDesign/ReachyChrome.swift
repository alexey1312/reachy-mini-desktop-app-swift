import SwiftUI

/// System chrome that only exists from iOS 26 / macOS 26, wrapped so a call site
/// never carries an `#available` of its own.
///
/// Each of these is a no-op below the floor rather than a fallback: there is no
/// older control that does the same thing, and pretending otherwise would build a
/// second design nobody asked for.
public extension View {
    /// Lets the tab bar step aside while the reader scrolls down a list.
    ///
    /// **`#if os(iOS)` and not an availability check alone.** The SDK declares
    /// `tabBarMinimizeBehavior` itself for macOS 26 — so reading the method's
    /// availability suggests no platform fork is needed — while every value of
    /// `TabBarMinimizeBehavior`, `.onScrollDown` included, is
    /// `@available(macOS, unavailable)`. The method compiles there and has nothing
    /// to pass it. Which is fitting: macOS has no tab bar to minimise.
    ///
    /// `isEnabled` is `.never` rather than a dropped modifier, so the behaviour can
    /// be switched off for as long as something else is pinned to the bottom of the
    /// window. A minimised bar and a bar that stepped aside are indistinguishable
    /// once an opaque strip occupies the row it would have shrunk into — which is
    /// what the running-app dock does, and how the tab bar came to be missing from
    /// the whole interface for as long as an app was running.
    @ViewBuilder
    func reachyMinimizingTabBar(_ isEnabled: Bool = true) -> some View {
        #if os(iOS)
            if #available(iOS 26.0, *) {
                tabBarMinimizeBehavior(isEnabled ? .onScrollDown : .never)
            } else {
                self
            }
        #else
            self
        #endif
    }

    /// Softens where scrolling content passes under a bar.
    ///
    /// Worth asking for only where the content is dense and unbroken — a log tail
    /// under a navigation bar. A grouped `Form` already ends in its own background,
    /// and softening that edge blurs a boundary the reader uses.
    @ViewBuilder
    func reachySoftScrollEdge(_ edges: Edge.Set) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }
}
