import ReachyDesign
import ReachyKit
import SwiftUI

/// The live view of the robot, floating over whatever tab is showing — and the
/// tab at the edge it leaves behind when it is switched off.
///
/// It draws `ViewportContent` and brings its own compact chrome: two icons rather
/// than the Live tab's segmented picker, which is up to 240 pt wide and does not
/// fit here.
///
/// **Nothing inside the window is interactive** — not the joystick (`makeTeleop` is
/// absent) and not the orbit camera (hit-testing is off on the content). The window
/// is one object that can be moved, put away and opened; the robot is driven from
/// the tab. That is a product decision and, since the scene's own gesture would
/// otherwise swallow every touch, also what makes the window work at all.
struct FloatingViewport: View {
    let model: FloatingViewportModel
    let viewport: ViewportModel
    let session: RobotSession
    /// The rectangle the window may occupy, already inset by the safe area — the
    /// tab bar and the running-app dock both live in that inset, and the window
    /// must not land on either.
    let bounds: CGRect
    /// Selects the Live tab. Called after the window has finished growing, never
    /// before: the tab and the window cannot both hold the viewport.
    let open: () -> Void

    var body: some View {
        switch model.placement {
        case .inline:
            EmptyView()
        case .floating:
            window
        case let .docked(edge, _):
            edgeTab(edge)
        }
    }

    // MARK: - The window

    /// The frame is animated by `isExpanding` and the content is handed over only
    /// once that animation reports itself done. A `matchedGeometryEffect` would be
    /// the obvious way to do this and is exactly what cannot be used: it keeps
    /// source and destination alive at the same time, and a second `RealityView`
    /// takes the robot away from the first.
    private var window: some View {
        let shape = Radius.rect(Radius.lg)
        return ViewportContent(model: viewport)
            // **The window's content is a picture, not a control.** `RobotSceneView`
            // hangs a `DragGesture(minimumDistance: 0)` off the `RealityView` for the
            // orbit camera, and in SwiftUI a descendant's gesture beats an ancestor's
            // `.gesture(_:)` — so every touch on the 3D pane went to the camera and
            // the window could be neither moved nor opened. The camera pane had no
            // such gesture and worked, which is what made the bug look 3D-only.
            //
            // Suppressed rather than out-prioritised with `highPriorityGesture`:
            // orbiting a 160 pt viewport is the same call as the absent `makeTeleop`
            // above, and both belong to full screen. The chrome is added *after*
            // this and stays live.
            .allowsHitTesting(false)
            .frame(width: windowSize.width, height: windowSize.height)
            .clipShape(shape)
            .reachySurface(.window, in: shape)
            .overlay(alignment: .topLeading) { switcher }
            .overlay(alignment: .bottomTrailing) { reconnectingBadge }
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .contentShape(.rect)
            // Everything below hangs off the window's own frame, and **`.position`
            // comes last on purpose**: it hands its child the parent's whole area to
            // sit in, so a gesture attached after it is scoped to the screen rather
            // than to the window. The translation is a delta either way, which is
            // what makes this a free correction rather than a rewrite.
            //
            // A non-zero minimum distance is what leaves the tap intact: at 0 the
            // drag claims every touch, and tapping the window is how it is opened.
            .gesture(drag)
            .onTapGesture(perform: openFullScreen)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(.reachy("Live view"))
            .accessibilityAddTraits(.isButton)
            .accessibilityActions { windowActions }
            .position(model.isExpanding ? CGPoint(x: bounds.midX, y: bounds.midY) : model.centre(in: bounds))
    }

    private var windowSize: CGSize {
        model.isExpanding ? bounds.size : Metrics.floatingViewport
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { model.dragChanged(translation: $0.translation, in: bounds) }
            .onEnded { value in
                withAnimation(Motion.springBack) {
                    model.dragEnded(translation: value.translation, in: bounds)
                }
            }
    }

    private func openFullScreen() {
        withAnimation(Motion.dock) {
            model.beginExpanding()
        } completion: {
            model.endExpanding()
            open()
        }
    }

    /// Two icons and no labels: at 160 pt there is room for the state, not for the
    /// word naming it. The Live tab keeps the picker, which is what a reader who
    /// wants to be told rather than shown is one tap away from.
    @ViewBuilder
    private var switcher: some View {
        if options.count > 1 {
            HStack(spacing: Space.xxs) {
                ForEach(options) { option in
                    Button {
                        viewport.setContent(option)
                    } label: {
                        Image(systemName: option.systemImage)
                            .font(Typography.status)
                            .foregroundStyle(option == viewport.content ? Tone.brand.style : Tone.quiet.style)
                            .frame(width: 24, height: 20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.xxs)
            .reachySurface(.chrome, in: .capsule)
            .padding(Space.xs)
        }
    }

    @ViewBuilder
    private var reconnectingBadge: some View {
        if isUnreachable {
            Image(systemName: "wifi.exclamationmark")
                .font(Typography.status)
                .foregroundStyle(Tone.warning.style)
                .padding(Space.xxs)
                .reachySurface(.chrome, in: .circle)
                .padding(Space.xs)
                .accessibilityLabel(.reachy("Unreachable — reconnecting…"))
        }
    }

    /// The window is one accessibility element — a 24 pt glyph inside a 160 pt
    /// window is not something VoiceOver can aim at — so everything it can do is
    /// offered as a named action instead. Without them the window could neither be
    /// opened nor put away, and it covers content.
    @ViewBuilder
    private var windowActions: some View {
        Button(.reachy("Open full screen"), action: openFullScreen)
        ForEach(options) { option in
            Button(option.title) { viewport.setContent(option) }
        }
        Button(.reachy("Hide at the leading edge")) { dock(.leading) }
        Button(.reachy("Hide at the trailing edge")) { dock(.trailing) }
    }

    private func dock(_ edge: HorizontalEdge) {
        withAnimation(Motion.dock) { model.dock(edge, in: bounds) }
    }

    // MARK: - The tab at the edge

    /// The off switch, and the way back. Flush with the screen edge, so it reads
    /// as something hanging off the side rather than as a shrunken window.
    ///
    /// **`.window` and not `.chrome`.** The role with no glass is the one that
    /// flips in a dark appearance and the one that does not smear where it meets
    /// the safe-area edge — both measured, both written up in
    /// `ReachyDesign/AGENTS.md`.
    private func edgeTab(_ edge: HorizontalEdge) -> some View {
        let leading = edge == .leading
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: leading ? 0 : Radius.lg,
            bottomLeadingRadius: leading ? 0 : Radius.lg,
            bottomTrailingRadius: leading ? Radius.lg : 0,
            topTrailingRadius: leading ? Radius.lg : 0,
            style: .continuous
        )
        return VStack(spacing: Space.xs) {
            Image(systemName: viewport.content.systemImage)
                .font(Typography.detail)
                .foregroundStyle(Tone.quiet.style)
            Circle()
                .fill(linkTone.style)
                .frame(width: Space.sm, height: Space.sm)
        }
        .frame(width: Metrics.viewportTab.width, height: Metrics.viewportTab.height)
        .background { ReachySurfaceFill(.window, in: shape) }
        .shadow(color: .black.opacity(0.2), radius: 8)
        .contentShape(.rect)
        // `.position` last, for the reason the window records: it gives its child
        // the whole area, and a tap attached after it would answer anywhere.
        .onTapGesture {
            withAnimation(Motion.dock) { model.undock(in: bounds) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(.reachy("Live view, hidden"))
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            Button(.reachy("Show the live view")) {
                withAnimation(Motion.dock) { model.undock(in: bounds) }
            }
        }
        .position(model.centre(in: bounds))
    }

    private var options: [ViewportModel.Content] {
        ViewportOptions.offered(by: viewport, offersCamera: session.hasCamera)
    }

    private var isUnreachable: Bool {
        if case .unreachable = session.phase {
            true
        } else {
            false
        }
    }

    private var linkTone: StatusTone {
        switch session.phase {
        case .connected: .active
        case .unreachable: .failed
        case .idle, .connecting: .idle
        }
    }
}

extension View {
    /// Floats the live view over the whole interface, wherever the shell draws a
    /// tab bar.
    ///
    /// **Apply this to the `TabView`.** Order against `reachyTabAccessory` no longer
    /// matters — it used to, back when the dock was a bottom `safeAreaInset` this
    /// overlay could read, and the note here said so. The strip is system chrome
    /// now, invisible to this reader like the tab bar, so `FloatingViewportModel`
    /// is told it is there instead.
    ///
    /// It is mounted in the shell rather than in the root so it dies with the
    /// connection. `.unreachable` stays in the shell, which is why a network blip
    /// leaves the window where it is instead of taking it away.
    func floatingViewport(
        model: FloatingViewportModel,
        viewport: ViewportModel,
        session: RobotSession,
        open: @escaping () -> Void
    ) -> some View {
        modifier(FloatingViewportModifier(model: model, viewport: viewport, session: session, open: open))
    }
}

private struct FloatingViewportModifier: ViewModifier {
    let model: FloatingViewportModel
    let viewport: ViewportModel
    let session: RobotSession
    let open: () -> Void

    #if !os(macOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// **The one size-class branch in this target, and it is deliberate.** The rule
    /// is not "iPhone" but "wherever the shell draws a tab bar rather than a
    /// sidebar": a sidebar layout has the Live tab permanently beside the others
    /// and nothing to float. `ReachyUI/AGENTS.md` carries the same note, because
    /// the entry there used to say no branch was left.
    private var hasTabBar: Bool {
        #if os(macOS)
            false
        #else
            horizontalSizeClass == .compact
        #endif
    }

    /// Asked of the model rather than of `RootViewportTarget`: the window renders
    /// what the model holds, and before it has attached there is nothing to float.
    /// The Live tab asks the other question because it has to say *why* there is no
    /// live view, which the model cannot tell it.
    private var hasSomethingToShow: Bool {
        viewport.source != nil && session.isAwake
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    let bounds = available(in: geometry)
                    if hasSomethingToShow, !model.isInline {
                        FloatingViewport(
                            model: model,
                            viewport: viewport,
                            session: session,
                            bounds: bounds,
                            open: open
                        )
                        .onChange(of: bounds) { _, new in model.fit(to: new) }
                    }
                }
            }
            .onChange(of: hasTabBar, initial: true) { _, value in
                model.hasTabBar = value
            }
    }

    /// The region the window may rest in: this reader's own, less the chrome it
    /// cannot see.
    ///
    /// **The safe area is not subtracted here, and that is the correction.** A
    /// `GeometryReader` is laid out *inside* the safe area, so `size` has already
    /// lost it and the origin of this reader's coordinate space — the space
    /// `.position` places the window in — is already the top-left of the inset
    /// region. Subtracting `safeAreaInsets` as well counted it twice at both ends.
    /// Measured on an iPhone 17 Pro running iOS 26.4: the reader is 402 × 778 and
    /// reports t62 b34, of a 402 × 874 screen. Reaching for `ignoresSafeArea()` on
    /// the reader does not fix it either — that yields the full 402 × 874 but
    /// reports t0 b0, so there would be nothing left to subtract.
    ///
    /// What does have to be subtracted is the chrome the reader is *not* inset by:
    /// the tab bar insets each tab's content and reports none of it out here, and
    /// the accessory the running-app strip sits in does the same, which is why the
    /// shell writes `hasBottomAccessory` rather than leaving it to be measured.
    private func available(in geometry: GeometryProxy) -> CGRect {
        let accessory = model.hasBottomAccessory ? Metrics.tabAccessoryAllowance : 0
        return CGRect(
            x: 0,
            y: 0,
            width: geometry.size.width,
            height: max(0, geometry.size.height - Metrics.tabBarAllowance - accessory)
        )
    }
}
