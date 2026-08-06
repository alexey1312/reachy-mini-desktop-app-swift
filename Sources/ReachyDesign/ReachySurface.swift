import SwiftUI

/// What a surface is *for*. A call site names this and never a material, a glass
/// or an OS version.
public enum SurfaceRole: Sendable, CaseIterable {
    /// A floating control over video or 3D, where nothing behind it can be relied
    /// on for contrast.
    case chrome
    /// A panel of content raised off whatever is behind it.
    case card
    /// A small marker sitting on content that already carries a surface.
    case badge
    /// The backdrop behind a header, a footer or a console.
    case scrim
}

public extension View {
    /// Two tiers, one call: real glass from iOS 26 / macOS 26, a material below.
    ///
    /// The opaque `baseFill` underneath the effect is what keeps the snapshot
    /// suite meaningful. Neither glass nor a material renders headless — the dock
    /// records the same about `.bar` — so without a fill that does render, every
    /// surface in the app would be invisible to the reference images, and the
    /// layout and text on each card would quietly lose their regression cover.
    func reachySurface(_ role: SurfaceRole, in shape: some Shape = .rect) -> some View {
        modifier(SurfaceBacking(role: role, shape: shape))
    }
}

private struct SurfaceBacking<S: Shape>: ViewModifier {
    let role: SurfaceRole
    let shape: S

    func body(content: Content) -> some View {
        effect(content).background { shape.fill(role.baseFill) }
    }

    /// `.glassEffect` is multiplatform, so there is no `#if os(…)` here and
    /// macOS 26 gets real glass — which an iOS-only backport never could.
    ///
    /// A role with neither takes its fill and nothing else.
    @ViewBuilder
    private func effect(_ content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), let glass = role.glass {
            content.glassEffect(glass, in: shape)
        } else if let material = role.material {
            content.background(material, in: shape)
        } else {
            content
        }
    }
}

extension SurfaceRole {
    var material: Material? {
        switch self {
        case .chrome, .card: .regular
        case .scrim: .bar
        case .badge: nil
        }
    }

    /// A badge gets no glass, and the reason is not restraint. `glassEffect`
    /// renders what it wraps vibrantly: measured on the iOS 26 simulator, red,
    /// orange, green and secondary all flatten to black inside one, and `.tint`
    /// is the single style that survives. Carrying a colour is a badge's whole
    /// job, so glass would take away the only thing it does. Nor does it need
    /// any: a badge sits inside a card, not floating over arbitrary content.
    @available(iOS 26.0, macOS 26.0, *)
    var glass: Glass? {
        switch self {
        // Only the chrome is touched. The rest are backdrops, and interactive
        // glass on one would react to every scroll passing under it.
        case .chrome: .regular.interactive()
        case .card, .scrim: .regular
        case .badge: nil
        }
    }

    /// A badge takes a fill rather than the window colour: it sits *on* a card,
    /// and `.background` there would punch a hole straight through to the screen.
    var baseFill: AnyShapeStyle {
        switch self {
        case .chrome, .card, .scrim: AnyShapeStyle(.background)
        case .badge: AnyShapeStyle(.fill.quaternary)
        }
    }
}
