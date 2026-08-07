import Foundation
import Observation
import ReachyKit

/// The robot's two destructive maintenance actions: clearing the Hugging Face
/// cache and uninstalling every app.
///
/// A model rather than `@State` on the card, because the interesting part is not
/// the two calls but the rule in front of one of them — and that rule is worth
/// asserting without a view.
@MainActor
@Observable
final class MaintenanceModel {
    enum Action: Equatable, Identifiable, CaseIterable {
        case clearHuggingFaceCache
        case resetApps

        var id: Self { self }
    }

    /// What the confirmation dialog is asking about. Not `private(set)` — the
    /// dialog's binding writes it back on dismissal.
    var confirming: Action?
    private(set) var running: Action?
    /// The last action that finished cleanly, so the card can say so in place.
    private(set) var finished: Action?
    private(set) var lastError: String?

    var isBusy: Bool {
        running != nil
    }

    /// Uninstalling every app is `shutil.rmtree("/venvs/apps_venv/")`, and the
    /// daemon neither stops a running app first nor puts anything back — the
    /// interpreter a live app is executing in simply goes away underneath it.
    /// The robot offers no protection there, so this is the client's, and the
    /// card says which app to stop rather than only greying the button out.
    ///
    /// An unfamiliar process state counts as running, the same way
    /// `RobotAppStatus.State.isBusy` treats it: refusing to delete an
    /// environment that might be in use is the safe way to be wrong.
    func blockingApp(_ session: RobotSession) -> RobotApp? {
        guard let status = session.runningApp, status.isBusy else { return nil }
        return status.app
    }

    func perform(_ action: Action, session: RobotSession) async {
        running = action
        finished = nil
        lastError = nil
        defer { running = nil }
        do {
            switch action {
            case .clearHuggingFaceCache: try await session.clearHuggingFaceCache()
            case .resetApps: try await session.resetApps()
            }
            finished = action
            // What the session last saw about installed apps is fiction now: the
            // venv every one of them lived in has just been deleted. Failing to
            // re-read is not worth reporting — the dock polls this anyway, and
            // the delete itself succeeded.
            if action == .resetApps {
                try? await session.refreshCurrentApp()
            }
        } catch {
            lastError.recordDaemonFailure(error)
        }
    }
}

#if DEBUG
    extension MaintenanceModel {
        /// In the model's own file rather than in `Previews/`: it writes
        /// `private(set)` members, which `@testable` does not reach.
        static func preview(
            confirming: Action? = nil,
            running: Action? = nil,
            finished: Action? = nil,
            error: String? = nil
        ) -> MaintenanceModel {
            let model = MaintenanceModel()
            model.confirming = confirming
            model.running = running
            model.finished = finished
            model.lastError = error
            return model
        }
    }
#endif
