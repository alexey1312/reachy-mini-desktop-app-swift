import ReachyKit
@testable import ReachyUI
import SwiftUI

/// Preview wrappers for the app store and the running-app dock.
///
/// Split out of `PreviewScenes.swift` only because that file is at its length
/// limit. Same rules apply: not `private`, because Prefire copies each preview body
/// into a generated file and anything a body names has to be visible target-wide.
@MainActor
extension PreviewScene {
    static func appStore(
        _ session: RobotSession,
        model: AppStoreModel? = nil,
        install: AppInstallModel? = nil
    ) -> some View {
        NavigationHost {
            AppStoreScreen(
                session: session,
                // Built on *this* session, not one of its own: the model reads the
                // running app through it, and two sessions would put the screen and
                // the dock on different robots.
                model: model ?? .preview(session: session),
                install: install ?? .preview(state: .idle, session: session)
            )
        }
        .preview()
    }

    /// The sheet the store opens, previewed on its own: it carries the whole
    /// install flow, and a snapshot of it is the only view of a job in flight.
    static func appDetail(
        _ session: RobotSession,
        app: RobotApp,
        model: AppStoreModel? = nil,
        install: AppInstallModel? = nil
    ) -> some View {
        NavigationHost {
            AppDetailSheet(
                app: app,
                model: model ?? .preview(session: session),
                session: session,
                install: install ?? .preview(state: .idle, session: session),
                dismiss: {}
            )
        }
        .preview()
    }

    /// The bottom strip on its own. Sized to fit rather than to a device: it is a
    /// component, and a full-screen capture of one would be mostly empty.
    static func runningAppDock(
        _ status: RobotAppStatus,
        conversationTurn: ConversationTurn? = nil,
        isReachable: Bool = true,
        busy: Bool = false
    ) -> some View {
        RunningAppDockContent(
            status: status,
            conversationTurn: conversationTurn,
            isReachable: isReachable,
            busy: busy,
            expand: {},
            perform: { _ in }
        )
        .preview()
    }

    /// The dock expanded. Parked through the session, which is where the running app
    /// lives — handing the sheet a status the session did not agree with would
    /// preview a state the app cannot reach.
    ///
    /// `conversationTurn` seeds the model this builds; a `model` passed in already
    /// carries its own turn, and then this argument has nothing left to say.
    static func runningAppSheet(
        _ status: RobotAppStatus,
        phase: RobotSession.ConnectionPhase = .connected(.preview),
        model: RunningAppModel? = nil,
        conversationTurn: ConversationTurn? = nil
    ) -> some View {
        NavigationHost {
            RunningAppSheet(
                session: .preview(phase: phase, runningApp: status),
                model: model ?? .preview(conversationTurn: conversationTurn),
                status: status
            )
        }
        .preview()
    }
}
