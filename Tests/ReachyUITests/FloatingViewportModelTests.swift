import CoreGraphics
import ReachyDesign
@testable import ReachyUI
import SwiftUI
import Testing

@MainActor
@Suite("Floating viewport", .timeLimit(.minutes(1)))
struct FloatingViewportModelTests {
    /// An iPhone's safe area, near enough: what matters is that the four corners
    /// are distinct and the window fits inside with room to spare.
    private static let portrait = CGRect(x: 0, y: 0, width: 400, height: 800)
    private static let landscape = CGRect(x: 0, y: 0, width: 800, height: 400)

    private func model(
        _ rest: FloatingViewportModel.Placement = .floating(.bottomTrailing),
        hasTabBar: Bool = true,
        live: Bool = false
    ) -> FloatingViewportModel {
        .preview(rest, hasTabBar: hasTabBar, isLiveTabSelected: live)
    }

    /// A gesture is two calls; `dragEnded` alone has no starting point to work from,
    /// which is the same thing SwiftUI guarantees.
    private func drag(_ model: FloatingViewportModel, by translation: CGSize, in bounds: CGRect) {
        model.dragChanged(translation: translation, in: bounds)
        model.dragEnded(translation: translation, in: bounds)
    }

    // MARK: - The placement automaton

    @Test("a fresh connection floats in a corner, live")
    func startsFloating() {
        let model = FloatingViewportModel()
        model.hasTabBar = true

        #expect(model.placement == .floating(.bottomTrailing))
        #expect(model.isStreaming)
        #expect(!model.isInline)
    }

    /// The single value both hosts read. There is no state in which the tab and the
    /// overlay would each draw a viewport, because there is nothing to disagree
    /// about — which is what keeps a second `RealityView` off the screen.
    @Test("the tab and the overlay never both draw")
    func exactlyOneHost() {
        let rests: [FloatingViewportModel.Placement] = [
            .floating(.topLeading),
            .floating(.bottomTrailing),
            .docked(.leading, y: 200),
            .docked(.trailing, y: 600),
        ]
        for rest in rests {
            for hasTabBar in [true, false] {
                for live in [true, false] {
                    let model = model(rest, hasTabBar: hasTabBar, live: live)
                    let tabDraws = model.isInline
                    let overlayDraws = !model.isInline
                    #expect(tabDraws != overlayDraws)
                    #expect(model.isInline == (model.placement == .inline))
                    #expect(!(model.isStreaming && model.isInline))
                }
            }
        }
    }

    @Test("selecting Live hands the viewport to the tab and gives it back")
    func inlineIsReversible() {
        let model = model()
        drag(model, by: CGSize(width: -300, height: -600), in: Self.portrait)
        let before = model.placement

        model.isLiveTabSelected = true
        #expect(model.placement == .inline)

        model.isLiveTabSelected = false
        #expect(model.placement == before)
    }

    /// A sidebar has the Live tab beside everything else, so there is nothing to
    /// float — and nothing that could leave a stream running behind a screen that
    /// is not showing it.
    @Test("no tab bar, no window, no stream")
    func regularWidthIsUnchanged() {
        let model = model(.floating(.topLeading), hasTabBar: false)

        #expect(model.placement == .inline)
        #expect(!model.isStreaming)
    }

    // MARK: - The off switch

    @Test("docking stops the stream and undocking starts it")
    func dockIsTheOffSwitch() {
        let model = model()

        model.dock(.leading, in: Self.portrait)
        #expect(model.placement == .docked(.leading, y: 728))
        #expect(!model.isStreaming)

        model.undock(in: Self.portrait)
        #expect(model.placement == .floating(.bottomLeading))
        #expect(model.isStreaming)
    }

    @Test("a docked window stays docked through a visit to the Live tab")
    func dockSurvivesInline() {
        let model = model()
        model.dock(.trailing, in: Self.portrait)

        model.isLiveTabSelected = true
        #expect(model.placement == .inline)
        #expect(!model.isStreaming)

        model.isLiveTabSelected = false
        #expect(model.placement == .docked(.trailing, y: 728))
        #expect(!model.isStreaming)
    }

    /// Neither the content switch nor a lost connection is an input to this model —
    /// which is the point. The window keeps its corner while the robot goes
    /// unreachable, and switching 3D for the camera moves nothing.
    @Test("nothing but a gesture or the tab moves the window")
    func placementHasNoOtherInputs() {
        let model = model(.docked(.leading, y: 300))
        let viewport = ViewportModel.preview()

        viewport.setContent(.camera)
        #expect(model.placement == .docked(.leading, y: 300))

        viewport.setContent(.scene)
        #expect(model.placement == .docked(.leading, y: 300))
    }

    // MARK: - Geometry

    @Test("each corner is a margin in from its own two edges", arguments: [
        (FloatingViewportModel.Corner.topLeading, CGPoint(x: 96, y: 72)),
        (.topTrailing, CGPoint(x: 304, y: 72)),
        (.bottomLeading, CGPoint(x: 96, y: 728)),
        (.bottomTrailing, CGPoint(x: 304, y: 728)),
    ])
    func cornerAnchors(corner: FloatingViewportModel.Corner, expected: CGPoint) {
        #expect(FloatingViewportModel.centre(of: corner, in: Self.portrait) == expected)
    }

    @Test("a drag that ends inside snaps to the nearest corner")
    func snapsToNearestCorner() {
        let model = model()
        // Bottom trailing is (304, 728); this lands in the top leading quadrant.
        drag(model, by: CGSize(width: -200, height: -600), in: Self.portrait)

        #expect(model.placement == .floating(.topLeading))
    }

    @Test("a drag stopping at the edge is still a drag, not a dock")
    func edgeWithoutOvershootDoesNotDock() {
        let model = model()
        // Far enough to reach the leading margin, not far enough past it.
        drag(model, by: CGSize(width: -220, height: 0), in: Self.portrait)

        #expect(model.placement == .floating(.bottomLeading))
    }

    @Test("carrying the window past an edge docks it there, at the height it was")
    func overshootDocks() {
        let leading = model()
        drag(leading, by: CGSize(width: -400, height: -400), in: Self.portrait)
        #expect(leading.placement == .docked(.leading, y: 328))

        let trailing = model(.floating(.topLeading))
        drag(trailing, by: CGSize(width: 400, height: 200), in: Self.portrait)
        #expect(trailing.placement == .docked(.trailing, y: 272))
    }

    @Test("the window never leaves the safe area, however far the finger goes")
    func dragIsClamped() {
        let model = model()
        model.dragChanged(translation: CGSize(width: -5000, height: -5000), in: Self.portrait)
        #expect(model.centre(in: Self.portrait) == CGPoint(x: 96, y: 72))

        model.dragChanged(translation: CGSize(width: 5000, height: 5000), in: Self.portrait)
        #expect(model.centre(in: Self.portrait) == CGPoint(x: 304, y: 728))
    }

    /// The corner is stored, not the point, so a rotation needs no migration — the
    /// same case simply resolves against the new rectangle.
    @Test("rotation re-resolves a floating corner")
    func rotationMovesTheCorner() {
        let model = model(.floating(.bottomTrailing))
        #expect(model.centre(in: Self.portrait) == CGPoint(x: 304, y: 728))

        model.fit(to: Self.landscape)
        #expect(model.placement == .floating(.bottomTrailing))
        #expect(model.centre(in: Self.landscape) == CGPoint(x: 704, y: 328))
    }

    /// A docked tab does carry a point, so it is the one thing rotation can strand.
    @Test("rotation pulls a docked tab back inside")
    func rotationClampsTheTab() {
        let model = model(.docked(.trailing, y: 700))

        model.fit(to: Self.landscape)
        #expect(model.placement == .docked(.trailing, y: 364))
        #expect(model.centre(in: Self.landscape) == CGPoint(x: 778, y: 364))
    }

    @Test("both edges put the tab flush against the screen", arguments: [
        (HorizontalEdge.leading, CGFloat(22)),
        (.trailing, CGFloat(378)),
    ])
    func tabHugsItsEdge(edge: HorizontalEdge, expectedX: CGFloat) {
        let model = model(.docked(edge, y: 400))

        #expect(model.centre(in: Self.portrait) == CGPoint(x: expectedX, y: 400))
    }

    /// A split view squeezed below the window's own size has no valid position at
    /// all. Centring is the only answer that is not off screen.
    @Test("a rectangle smaller than the window centres it rather than losing it")
    func degenerateBoundsCentre() {
        let tiny = CGRect(x: 0, y: 0, width: 80, height: 60)
        let middle = CGPoint(x: 40, y: 30)

        #expect(FloatingViewportModel.centre(of: .topLeading, in: tiny) == middle)
        #expect(FloatingViewportModel.centre(of: .bottomTrailing, in: tiny) == middle)
        #expect(FloatingViewportModel.clamped(CGPoint(x: 999, y: 999), in: tiny) == middle)
        #expect(FloatingViewportModel.nearestCorner(to: .zero, in: .zero) == nil)
    }
}
