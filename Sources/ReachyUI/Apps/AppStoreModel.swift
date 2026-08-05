import Foundation
import Observation
import ReachyKit

/// Drives the robot's app store: what is installed, what could be, and what is
/// running right now.
@MainActor
@Observable
final class AppStoreModel {
    enum Section: Int, CaseIterable, Identifiable {
        case installed
        case discover

        var id: Int {
            rawValue
        }

        var title: String {
            switch self {
            case .installed: "Installed"
            case .discover: "Discover"
            }
        }
    }

    var section: Section = .installed
    var searchText = ""

    private(set) var installed: [RobotApp] = []
    private(set) var catalogue: [RobotApp] = []
    private(set) var runningApp: RobotAppStatus?
    private(set) var startupApp: String?
    private(set) var updates: AppUpdatesSummary?
    private(set) var lock: RobotAppLockStatus?
    private(set) var loading = false
    private(set) var busy = false
    private(set) var lastError: String?

    /// Coalesces overlapping loads: a slow catalogue must not overwrite the result
    /// of a refresh the user asked for afterwards (`MovesModel`'s pattern).
    private var loadID: UUID?

    var visibleApps: [RobotApp] {
        let apps = switch section {
        case .installed: installed
        case .discover: catalogue
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.matchesSearch(query) }
    }

    /// The installed row a catalogue card stands for. Everything the daemon does to
    /// an app — start, stop, remove, update, auto-start — is keyed by *that* name,
    /// which the Space author chose independently of the slug.
    func installedTwin(of app: RobotApp) -> RobotApp? {
        if app.isInstalled {
            return app
        }
        return installed.first { app.matches(installed: $0) }
    }

    func isInstalled(_ app: RobotApp) -> Bool {
        installedTwin(of: app) != nil
    }

    func hasUpdate(_ app: RobotApp) -> Bool {
        guard let updates, let twin = installedTwin(of: app) else { return false }
        return updates.hasUpdate(for: twin) || updates.hasUpdate(for: app)
    }

    func isRunning(_ app: RobotApp) -> Bool {
        guard let runningApp, let twin = installedTwin(of: app) else { return false }
        return runningApp.app.name == twin.name
    }

    func isStartupApp(_ app: RobotApp) -> Bool {
        guard let startupApp, let twin = installedTwin(of: app) else { return false }
        return startupApp == twin.name
    }

    /// Someone is driving this robot from outside the LAN. Worth distinguishing
    /// from a local app: the user cannot simply stop it from here.
    var isHeldRemotely: Bool {
        lock?.state == .remoteSession
    }

    var lockHolder: String? {
        lock?.holderName
    }

    func load(session: RobotSession, refresh: Bool = false) async {
        let requestID = UUID()
        loadID = requestID
        loading = true
        defer {
            if loadID == requestID {
                loading = false
            }
        }

        do {
            // One `list-available` carries the catalogue and the installed list
            // together (`list_all_available_apps`), so the two sections cost one
            // round trip rather than two.
            let apps = try await session.appCatalogue(refresh: refresh)
            guard loadID == requestID, !Task.isCancelled else { return }
            catalogue = apps.filter { !$0.isInstalled }
            installed = apps.filter(\.isInstalled)
            lastError = nil
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            catalogue = []
            installed = []
            lastError = Self.describe(error)
            return
        }

        // Everything below is decoration: a robot whose store loaded is usable
        // even if its update check timed out.
        runningApp = try? await session.currentApp()
        lock = try? await session.appLockStatus()
        startupApp = try? await session.startupApp()
        updates = try? await session.appUpdates()
    }

    func start(_ app: RobotApp, session: RobotSession) async {
        guard let twin = installedTwin(of: app) else { return }
        await run { runningApp = try await session.startApp(named: twin.name) }
    }

    func stop(session: RobotSession) async {
        await run {
            try await session.stopCurrentApp()
            runningApp = nil
        }
    }

    func restart(session: RobotSession) async {
        await run { runningApp = try await session.restartCurrentApp() }
    }

    /// `nil` clears it. Sent under the installed name, which is the only one the
    /// daemon will accept.
    func setStartupApp(_ app: RobotApp?, session: RobotSession) async {
        let name = app.flatMap { installedTwin(of: $0)?.name }
        await run { startupApp = try await session.setStartupApp(name) }
    }

    /// Re-reads what an install or removal changed, without re-fetching the
    /// catalogue from Hugging Face.
    func reloadInstalled(session: RobotSession) async {
        installed = await (try? session.installedApps(refresh: true)) ?? installed
        runningApp = try? await session.currentApp()
        startupApp = try? await session.startupApp()
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension RobotApp {
    /// Title, name, author and Space id all answer — a user who knows an app by
    /// its Hub URL should find it by pasting the owner in.
    func matchesSearch(_ query: String) -> Bool {
        [title, name, author, spaceID, summary]
            .compactMap(\.self)
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

#if DEBUG
    extension AppStoreModel {
        /// A store parked in one state. Lives here rather than in `Previews/`:
        /// everything it writes is `private(set)`, which `@testable` does not reach
        /// from another module.
        static func preview(
            section: Section = .discover,
            catalogue: [RobotApp] = RobotApp.previewCatalogue,
            installed: [RobotApp] = RobotApp.previewInstalled,
            running: RobotAppStatus? = nil,
            startupApp: String? = nil,
            hasUpdate: Bool = false,
            lock: RobotAppLockStatus? = nil,
            loading: Bool = false,
            error: String? = nil
        ) -> AppStoreModel {
            let model = AppStoreModel()
            model.section = section
            model.catalogue = catalogue
            model.installed = installed
            model.runningApp = running
            model.startupApp = startupApp
            model.lock = lock
            model.loading = loading
            model.lastError = error
            if hasUpdate, let first = installed.first {
                model.updates = .preview(appName: first.name)
            }
            return model
        }
    }

    extension AppUpdatesSummary {
        static func preview(appName: String) -> AppUpdatesSummary {
            let json = """
            {"apps_with_updates": [{"app_name": "\(appName)", "space_id": "pollen-robotics/\(appName)",
              "installed_sha": "a1b2c3", "latest_sha": "d4e5f6", "update_available": true}],
             "apps_checked": 2, "apps_skipped": 0}
            """
            // swiftlint:disable:next force_try
            return try! AppUpdatesSummary(JSONDecoder().decode(
                Components.Schemas.AppUpdatesResponse.self,
                from: Data(json.utf8)
            ))
        }
    }
#endif
