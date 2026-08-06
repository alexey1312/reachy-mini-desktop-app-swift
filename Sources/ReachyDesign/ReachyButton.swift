import SwiftUI

/// How much a button insists.
public enum ButtonEmphasis: Sendable, CaseIterable {
    /// The action the screen is there for. One per screen, at most.
    case prominent
    /// An action beside it.
    case standard
    /// A way out, or an alternative the reader is not being steered towards.
    ///
    /// Added for the connection rail's decisions, where three bordered capsules of
    /// different widths stacked into a ragged column — legible, and plainly wrong.
    /// A borderless label carries no width of its own, so several sit on one line
    /// without competing with the action above them and without clipping when the
    /// text grows.
    case quiet
}

public extension View {
    /// The app's action button. A call site names emphasis, never a style.
    ///
    /// **There is no glass tier here, and that is a measurement rather than a
    /// preference.** `.buttonStyle(.glass)` does not merely fail to render in a
    /// headless snapshot the way a material does — it takes the whole capture with
    /// it. A screen carrying one comes out blank apart from its toolbar, which is
    /// rendered in a separate pass. Measured by recording the onboarding suite
    /// twice on the iOS 26 simulator: with the glass tier every reference was
    /// empty, with it removed every one was complete, nothing else changed.
    ///
    /// A blank reference is worse than a missing one — it reads as coverage and
    /// passes any change (`ReachyUI/AGENTS.md`) — and roughly sixty of them sit
    /// behind these fourteen call sites. So the styles stay bordered, which iOS 26
    /// draws in its own updated way regardless.
    ///
    /// Glass as a *background* is unaffected and is what `reachySurface` uses: the
    /// viewport's chrome renders correctly through the same simulator. The
    /// difference is that a button style wraps its content and a background does
    /// not — the same distinction that costs a wrapped foreground its colour.
    func reachyButton(_ emphasis: ButtonEmphasis = .standard) -> some View {
        modifier(ReachyButtonStyle(emphasis: emphasis))
    }
}

private struct ReachyButtonStyle: ViewModifier {
    let emphasis: ButtonEmphasis

    func body(content: Content) -> some View {
        switch emphasis {
        case .prominent: content.buttonStyle(.borderedProminent)
        case .standard: content.buttonStyle(.bordered)
        // `.borderless` rather than `.plain`: plain drops the tint too, and a
        // tintless label beside a blue one reads as disabled.
        case .quiet: content.buttonStyle(.borderless)
        }
    }
}
