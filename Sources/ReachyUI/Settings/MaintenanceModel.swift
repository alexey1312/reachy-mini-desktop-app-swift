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

        var id: Self {
            self
        }
    }

    /// What the confirmation dialog is asking about. Not `private(set)` — the
    /// dialog's binding writes it back on dismissal.
    var confirming: Action?
    private(set) var running: Action?
    /// The last action that finished cleanly, so the card can say so in place.
    private(set) var finished: Action?
    private(set) var lastError: String?

    /// The apps `reset-apps` is about to delete, so the confirmation can name them.
    ///
    /// **This list cannot be recovered afterwards.** `rmtree` takes the venv whole
    /// and no daemon route reports what used to be in it — after the 2026-08-08
    /// incident the only way left to find out was `journalctl` on the robot. Naming
    /// them at the moment of the decision is both the warning and the record.
    private(set) var installed: [RobotApp] = []

    var isBusy: Bool {
        running != nil
    }

    /// The apps about to go, named, or nil when the list could not be read — the
    /// dialog then says "every app" rather than implying the robot has none.
    ///
    /// Here rather than on the card because a dialog's *copy* is model logic: a
    /// `confirmationDialog` presents in a context of its own that captures as
    /// nothing, so no reference image can ever show this sentence and a model test
    /// is the only thing that can hold it (`Sources/ReachyUI/AGENTS.md`).
    ///
    /// `.list(type: .and)` rather than joining with commas: the conjunction and the
    /// separator both differ by language, and this string is translated.
    var installedSummary: String? {
        let titles = installed.map(\.title)
        guard !titles.isEmpty else { return nil }
        return titles.formatted(.list(type: .and))
    }

    /// Read once when the card appears. The session caches the answer, and an empty
    /// result is indistinguishable from a failed read on purpose: the dialog then
    /// falls back to saying "every app" rather than claiming the robot has none.
    func loadInstalled(session: RobotSession) async {
        guard session.canPerformMaintenance else { return }
        installed = await (try? session.installedApps()) ?? []
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
            //
            // The local list goes with it. It is read once when the card appears and
            // nothing re-reads it, so leaving it would have the next confirmation
            // name the apps this call deleted, under a sentence saying they are
            // about to be.
            if action == .resetApps {
                installed = []
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
            error: String? = nil,
            installed: [RobotApp] = []
        ) -> MaintenanceModel {
            let model = MaintenanceModel()
            model.confirming = confirming
            model.running = running
            model.finished = finished
            model.lastError = error
            model.installed = installed
            return model
        }
    }
#endif
