import Observation
import ReachyDesign
import SwiftUI

/// Where the one live view of the robot is drawn, and the geometry of the window
/// that carries it off the Live tab.
///
/// **`placement` is derived, never assigned.** `LiveTab` draws the viewport only
/// at `.inline` and the overlay only at everything else, so the two predicates
/// come out of a single value and there is no state in which both are true. That
/// is what keeps `ReachyScene/AGENTS.md`'s "move the view; never mount two" true
/// by construction rather than by review — an `Entity` has one parent, and a
/// second `RealityView` would silently take the robot from the first.
///
/// The gesture's starting values are stored properties rather than
/// `@GestureState`, which is the shape `OrbitCamera` already uses and the only one
/// in this project.
@MainActor
@Observable
final class FloatingViewportModel {
    /// Which corner the window rests in. Stored as a corner and not as a point, so
    /// a rotation or a split-view resize needs no migration at all.
    enum Corner: Hashable, CaseIterable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    enum Placement: Equatable {
        /// The Live tab draws the viewport, full size. Also the whole of the story
        /// on a regular width, where there is no floating window.
        case inline
        /// The overlay draws it and the stream is running.
        case floating(Corner)
        /// The overlay draws a tab at the edge and the stream is stopped. `y` is
        /// the tab's centre, kept from wherever the window was let go of.
        case docked(HorizontalEdge, y: CGFloat)
    }

    /// Where the window sits whenever the tab does not have it. Never `.inline` —
    /// that case belongs to `placement`, which is what merges this with the two
    /// inputs below.
    private(set) var rest: Placement = .floating(.bottomTrailing)

    /// Whether the shell is showing a tab bar rather than a sidebar. Written by
    /// the modifier that mounts the overlay, because that is the one place the
    /// size class is read.
    ///
    /// False collapses everything back to today's behaviour: the viewport is the
    /// tab's, always, and `isStreaming` is never true — so a sidebar layout cannot
    /// leave a stream running behind a screen that is not showing it.
    var hasTabBar = false

    /// Whether the Live tab is the selected one. Written by the shell.
    var isLiveTabSelected = false

    /// Whether the running-app strip is on screen. Written by the shell, because
    /// neither placement the strip can take is reported to the overlay's safe area —
    /// the system's accessory slot is invisible to it for the same reason the tab
    /// bar is, and the fallback's inset sits *inside* a tab, one level further in
    /// than the overlay can see.
    var hasBottomAccessory = false

    /// Set while the window grows to fill the screen, in the instant before the
    /// tab takes the viewport over. There is no matched transition to be had here
    /// — that would need both hosts alive at once — so the overlay animates its
    /// own frame and hands the content over only once it is done.
    private(set) var isExpanding = false

    /// The window's centre while a finger is on it. `nil` at rest, where the
    /// corner decides.
    private(set) var dragCentre: CGPoint?
    private var dragStart: CGPoint?

    var placement: Placement {
        isLiveTabSelected || !hasTabBar ? .inline : rest
    }

    /// Whether the tab owns the viewport. The overlay draws exactly when this is
    /// false, and `LiveTab` exactly when it is true.
    var isInline: Bool {
        placement == .inline
    }

    /// The one thing `RootLifecycle` asks: is anything outside the Live tab
    /// keeping the stream alive? A docked window is the off switch, so it is not.
    var isStreaming: Bool {
        if case .floating = placement {
            true
        } else {
            false
        }
    }

    // MARK: - Placement

    /// The window was tapped: grow it, then let the caller select the tab. Split
    /// in two so the model never has to know what a `router` is.
    func beginExpanding() {
        isExpanding = true
    }

    func endExpanding() {
        isExpanding = false
    }

    /// Switches the window off at an edge, keeping the height it was at. The one
    /// lever the user has over the stream, and the reason `isStreaming` exists.
    func dock(_ edge: HorizontalEdge, in bounds: CGRect) {
        guard case .floating = rest else { return }
        rest = .docked(edge, y: Self.clampedTabY(centre(in: bounds).y, in: bounds))
    }

    /// The tab at the edge was tapped. The window comes back to whichever corner
    /// is nearest where it was hiding, and the stream comes back with it.
    func undock(in bounds: CGRect) {
        guard case let .docked(edge, y) = rest else { return }
        let centre = Self.tabCentre(edge: edge, y: y, in: bounds)
        // A degenerate rectangle has no nearest anything; the edge it was hiding at
        // is still the side it should come back to.
        let fallback: Corner = edge == .leading ? .bottomLeading : .bottomTrailing
        rest = .floating(Self.nearestCorner(to: centre, in: bounds) ?? fallback)
    }

    /// Keeps a docked tab inside a rotated or resized screen. A floating window
    /// needs nothing — its corner is already relative.
    func fit(to bounds: CGRect) {
        guard case let .docked(edge, y) = rest else { return }
        rest = .docked(edge, y: Self.clampedTabY(y, in: bounds))
    }

    // MARK: - Dragging

    /// Where to draw the window's centre right now.
    func centre(in bounds: CGRect) -> CGPoint {
        if let dragCentre {
            return dragCentre
        }
        switch rest {
        case .inline, .floating:
            return Self.centre(of: restingCorner, in: bounds)
        case let .docked(edge, y):
            return Self.tabCentre(edge: edge, y: y, in: bounds)
        }
    }

    func dragChanged(translation: CGSize, in bounds: CGRect) {
        guard case let .floating(corner) = rest else { return }
        let start = dragStart ?? Self.centre(of: corner, in: bounds)
        dragStart = start
        let moved = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        dragCentre = Self.clamped(moved, in: bounds)
    }

    /// A drag that carried the window past an edge switches it off; anything else
    /// snaps to the nearest corner.
    ///
    /// The test is the *unclamped* position, not the drawn one: the window stops
    /// at the margin while the finger keeps going, and that overshoot is the whole
    /// signal. Without it a drag that merely ended at the edge would dock, and the
    /// stream would stop because someone parked the window on the left.
    func dragEnded(translation: CGSize, in bounds: CGRect) {
        defer {
            dragStart = nil
            dragCentre = nil
        }
        guard case let .floating(corner) = rest, let start = dragStart else { return }
        let moved = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let resting = Self.clamped(moved, in: bounds)
        if moved.x < resting.x - Self.dockOvershoot {
            rest = .docked(.leading, y: Self.clampedTabY(moved.y, in: bounds))
        } else if moved.x > resting.x + Self.dockOvershoot {
            rest = .docked(.trailing, y: Self.clampedTabY(moved.y, in: bounds))
        } else {
            rest = .floating(Self.nearestCorner(to: resting, in: bounds) ?? corner)
        }
    }

    /// The corner a floating window rests in, and the one a docked one came from —
    /// the tab's icons need something to draw even while the window is away.
    private var restingCorner: Corner {
        if case let .floating(corner) = rest {
            corner
        } else {
            .bottomTrailing
        }
    }
}

// MARK: - Geometry

/// Pure, and deliberately static: every one of these is a function of a rectangle
/// and a point, so the whole placement automaton is testable with no view around
/// it.
extension FloatingViewportModel {
    /// How far past the margin the finger has to travel before letting go docks
    /// the window rather than snapping it back.
    static let dockOvershoot: CGFloat = 44

    /// Clamped as well as anchored, so a rectangle too small to hold the window —
    /// a squeezed split view, a preview given no size — still yields a point on
    /// screen rather than one off the far edge.
    static func centre(
        of corner: Corner,
        in bounds: CGRect,
        size: CGSize = Metrics.floatingViewport,
        margin: CGFloat = Space.lg
    ) -> CGPoint {
        clamped(
            CGPoint(
                x: corner.isLeading ? bounds.minX : bounds.maxX,
                y: corner.isTop ? bounds.minY : bounds.maxY
            ),
            in: bounds,
            size: size,
            margin: margin
        )
    }

    /// Which quadrant of `bounds` a point is in. `nil` only for a degenerate
    /// rectangle, where "nearest" means nothing and the caller keeps what it had.
    static func nearestCorner(to point: CGPoint, in bounds: CGRect) -> Corner? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        switch (point.x < bounds.midX, point.y < bounds.midY) {
        case (true, true): return .topLeading
        case (false, true): return .topTrailing
        case (true, false): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    static func clamped(
        _ centre: CGPoint,
        in bounds: CGRect,
        size: CGSize = Metrics.floatingViewport,
        margin: CGFloat = Space.lg
    ) -> CGPoint {
        CGPoint(
            x: clamp(
                centre.x,
                bounds.minX + margin + size.width / 2,
                bounds.maxX - margin - size.width / 2
            ),
            y: clamp(
                centre.y,
                bounds.minY + margin + size.height / 2,
                bounds.maxY - margin - size.height / 2
            )
        )
    }

    /// The tab is flush with the edge — no margin, that is what makes it read as
    /// something hanging off the side rather than as a shrunken window.
    static func tabCentre(
        edge: HorizontalEdge,
        y: CGFloat,
        in bounds: CGRect,
        size: CGSize = Metrics.viewportTab
    ) -> CGPoint {
        CGPoint(
            x: edge == .leading
                ? bounds.minX + size.width / 2
                : bounds.maxX - size.width / 2,
            y: clampedTabY(y, in: bounds, size: size)
        )
    }

    static func clampedTabY(
        _ y: CGFloat,
        in bounds: CGRect,
        size: CGSize = Metrics.viewportTab
    ) -> CGFloat {
        clamp(y, bounds.minY + size.height / 2, bounds.maxY - size.height / 2)
    }

    /// An inverted range means the window does not fit at all — a split view
    /// squeezed to nothing, a preview given no size. Centring is the only answer
    /// that is not off screen.
    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}

extension FloatingViewportModel.Corner {
    var isLeading: Bool {
        self == .topLeading || self == .bottomLeading
    }

    var isTop: Bool {
        self == .topLeading || self == .topTrailing
    }
}

#if DEBUG
    extension FloatingViewportModel {
        /// Parked in a placement a real gesture would have to reach. `rest` is
        /// `private(set)`, which is why this lives here rather than in `Previews/`.
        static func preview(
            _ rest: Placement = .floating(.bottomTrailing),
            hasTabBar: Bool = true,
            isLiveTabSelected: Bool = false
        ) -> FloatingViewportModel {
            let model = FloatingViewportModel()
            model.rest = rest
            model.hasTabBar = hasTabBar
            model.isLiveTabSelected = isLiveTabSelected
            return model
        }
    }
#endif
