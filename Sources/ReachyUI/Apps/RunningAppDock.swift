import ReachyKit
import ReachyWidgetUI
import SwiftUI

/// The running app, pinned to the bottom of the window under everything else.
///
/// Mounted as a bottom `safeAreaInset` on the root `TabView`, so it sits *below*
/// the tab bar and the whole interface shrinks to make room — the shape Telegram
/// uses for a minimized Mini App, rather than the Apple-Music accessory that rides
/// above the bar. Tapping it opens the full sheet; dismissing that sheet comes back
/// here without stopping the app.
struct RunningAppDock: View {
    let session: RobotSession
    let model: RunningAppModel

    var body: some View {
        Group {
            if let status = model.visibleStatus(for: session) {
                RunningAppDockContent(
                    status: status,
                    isReachable: model.isReachable(session),
                    busy: model.busy,
                    expand: { model.isExpanded = true },
                    perform: perform
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: isVisible)
        // Without this the strip rides up on top of the keyboard whenever the Apps
        // search field takes focus. Being covered is the least surprising thing a
        // pinned bar can do.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Animate on the appearance, not on every status change: re-running the
    /// transition because the caption went from "Starting…" to "Running" would slide
    /// the whole interface for a word.
    private var isVisible: Bool {
        model.visibleStatus(for: session) != nil
    }

    private func perform(_ action: RunningAppDockContent.Action) {
        Task {
            switch action {
            case .stop: await model.stop(session: session)
            case .restart: await model.restart(session: session)
            case .dismiss: model.dismissFailure(session)
            }
        }
    }
}

extension View {
    /// Pins the running-app dock under the whole interface, opens its sheet, and
    /// keeps its reading fresh.
    ///
    /// **Apply this to the `TabView`, never to a tab's content.** A bottom
    /// `safeAreaInset` shrinks the safe area of the view it is applied to, and the
    /// tab bar lays itself out inside that — so on the `TabView` the bar moves up
    /// and the strip lands *below* it, which is what a minimized Telegram Mini App
    /// does. On a tab's content the same modifier puts the strip *above* the bar,
    /// which is the Apple-Music accessory and a different feature.
    ///
    /// It lives here rather than in the root view because that reasoning belongs
    /// next to the thing it is about — and because the root view is already at its
    /// length limit.
    func runningAppDock(session: RobotSession, model: RunningAppModel) -> some View {
        modifier(RunningAppDockModifier(session: session, model: model))
    }
}

private struct RunningAppDockModifier: ViewModifier {
    let session: RobotSession
    let model: RunningAppModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.reachyPreviewMode) private var previewMode

    /// Which app holds the robot has no push channel — `/api/state/ws/full` carries
    /// nothing about apps — so it has to be asked for. Not while backgrounded, and
    /// not over a relay: `RemoteRobotConnection` does not speak the apps protocol,
    /// so every tick would simply throw `.appsUnavailable`.
    private var polls: Bool {
        scenePhase == .active && model.canPoll(session) && !previewMode
    }

    private var visibleStatus: RobotAppStatus? {
        model.visibleStatus(for: session)
    }

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RunningAppDock(session: session, model: self.model)
            }
            .sheet(isPresented: $model.isExpanded) {
                // Read afresh rather than captured: an app that stops while the
                // sheet is open should close it, not leave a page about a process
                // that no longer exists.
                if let status = visibleStatus {
                    NavigationStack {
                        RunningAppSheet(session: session, model: self.model, status: status)
                    }
                    .presentationDetents([.large])
                }
            }
            .task(id: polls) {
                guard polls else { return }
                await self.model.poll(session: session)
            }
            .onChange(of: visibleStatus) { _, status in
                self.model.visibleStatusChanged(status)
            }
    }
}

/// The strip itself. Split from its container so it can be previewed at
/// `.sizeThatFitsLayout` without a root view around it.
struct RunningAppDockContent: View {
    enum Action {
        case stop
        case restart
        /// Only offered for a dead app: there is nothing left to stop, and the row
        /// would otherwise sit there forever.
        case dismiss
    }

    let status: RobotAppStatus
    var isReachable = true
    var busy = false
    let expand: () -> Void
    let perform: (Action) -> Void

    private var hasFailed: Bool {
        status.state == .error
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: expand) {
                HStack(spacing: 12) {
                    AppArtworkTile(app: status.app, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.app.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        RunningAppStatusChip(status: status, isReachable: isReachable)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the running app")

            if hasFailed {
                dismissButton
            } else {
                restartButton
                stopButton
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: Self.contentHeight)
        .background { windowEdge }
    }

    /// Telegram's own numbers, read off `MinimizedContainer.swift`: a 56 pt strip
    /// (`minimizedNavigationHeight`) under a 25 pt corner radius
    /// (`containerNode.cornerRadius`), with a shadow behind it.
    private static let contentHeight: CGFloat = 56
    private static let cornerRadius: CGFloat = 25

    /// What makes the strip read as a *window under the app* rather than as a
    /// toolbar belonging to it: a rounded top edge with a shadow above it. A flat
    /// full-bleed bar with a hairline divider says the opposite — that it is part of
    /// the screen it is pinned to.
    ///
    /// Two fills, and the lower one is load-bearing: nothing may show through a
    /// window. `.bar` alone is translucent — on iPad the Disconnect card behind it
    /// read straight through — and it does not render at all in a headless snapshot,
    /// which is the same reason the tab bar's glass is absent from every root
    /// capture. `.background` is the semantic style, not a pinned colour, so it
    /// follows the appearance and avoids the trap `ReachyUI/AGENTS.md` records for
    /// `Color.black` under adaptive chrome.
    ///
    /// The shape reaches past the home indicator so the fill runs to the screen
    /// edge; only its top corners are rounded, since the rest is off-screen.
    private var windowEdge: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Self.cornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Self.cornerRadius,
            style: .continuous
        )
        return shape
            .fill(.background)
            .overlay { shape.fill(.bar) }
            .shadow(color: .black.opacity(0.15), radius: 10, y: -1)
            .ignoresSafeArea(edges: .bottom)
    }

    private var restartButton: some View {
        Button {
            perform(.restart)
        } label: {
            Label("Restart", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(busy || !isReachable)
    }

    private var stopButton: some View {
        Button {
            perform(.stop)
        } label: {
            Label("Stop", systemImage: "stop.fill")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(.red)
        .disabled(busy || !isReachable)
    }

    private var dismissButton: some View {
        Button {
            perform(.dismiss)
        } label: {
            Label("Dismiss", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }
}
