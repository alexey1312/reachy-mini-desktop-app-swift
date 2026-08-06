import HuggingFaceAuth
import ReachyKit
import ReachyMedia
import SwiftUI

/// Every effect the root runs, in one place.
///
/// Applied with `.modifier(_:)` rather than through a `View` extension like its
/// neighbours: the cluster needs seven collaborators, and a helper taking seven
/// arguments is a SwiftLint violation while a memberwise initialiser is not.
struct RootLifecycle: ViewModifier {
    let session: RobotSession
    let viewport: ViewportModel
    let floating: FloatingViewportModel
    let hfAccount: HFAccount
    let remoteRobots: YourReachiesModel
    let runningApp: RunningAppModel
    let router: ReachyRouter
    @Binding var remoteLink: RemoteRobotLink?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.reachyPreviewMode) private var previewMode

    func body(content: Content) -> some View {
        content
            .task {
                guard !previewMode else { return }
                hfAccount.restore()
            }
            .onChange(of: hfAccount.state, initial: true) { _, _ in
                guard !previewMode else { return }
                remoteRobots.accountChanged()
            }
            .task(id: viewportTarget) {
                guard !previewMode else { return }
                if let viewportTarget {
                    viewport.attach(to: viewportTarget)
                } else {
                    viewport.detach()
                }
            }
            .onChange(of: viewportIsOnScreen, initial: true) { _, onScreen in
                guard !previewMode else { return }
                viewport.setActive(onScreen)
            }
            .onChange(of: keepsRemoteLinkAlive) { _, keepAlive in
                guard !keepAlive else { return }
                stopRemoteLink()
            }
            .onOpenURL { url in
                // Only a destination this app owns. The OAuth callback shares this
                // scheme and belongs to the sign-in session, so `ReachyDeepLink`
                // refuses it rather than landing the user on a tab mid-authorisation.
                guard let link = ReachyDeepLink(url: url) else { return }
                router.follow(link)
                if case .runningApp = link {
                    runningApp.requestExpansion(for: session)
                }
            }
            .widgetReload(session: session, isPreview: previewMode)
    }

    /// Both the geometry and the state routes sit behind the backend, so a link
    /// alone is not enough to show anything.
    ///
    /// Over the relay the camera is the peer connection `RemoteRobotLink` already
    /// holds — the same one carrying the commands — rather than one this view would
    /// dial. Reading `session.address` here is what used to make the Live tab
    /// impossible to reach from outside the robot's network.
    private var viewportTarget: ViewportModel.Source? {
        RootViewportTarget.source(session: session, remoteLink: remoteLink)
    }

    /// The single lever for battery: nothing streams unless the viewport is the
    /// thing the user is actually looking at — and a sleeping robot is never that,
    /// however visible the tab is.
    ///
    /// Two ways of being looked at now, not one. The floating window is the second,
    /// and its tab at the edge is what turns it off: `isStreaming` is false the
    /// moment the window is docked, and false on a regular width, where there is no
    /// window at all.
    private var viewportIsOnScreen: Bool {
        guard scenePhase == .active, viewportTarget != nil, session.isAwake else { return false }
        return router.tab == .live || floating.isStreaming
    }

    private var keepsRemoteLinkAlive: Bool {
        RemoteLinkLifetime.shouldKeepAlive(isRemote: session.isRemote, phase: session.phase)
    }

    private func stopRemoteLink() {
        remoteLink?.stop()
        remoteLink = nil
    }
}

/// Shared by the lifecycle, which decides when to stream, and the Live tab, which
/// decides what to draw. Both ask the same question and must not drift.
enum RootViewportTarget {
    @MainActor
    static func source(session: RobotSession, remoteLink: RemoteRobotLink?) -> ViewportModel.Source? {
        guard session.isBackendRunning else { return nil }
        switch session.link {
        case let .lan(address): return .lan(address)
        case .remote: return remoteLink.map { .remote($0.camera) }
        case .none: return nil
        }
    }
}
