import AppIntents
import Foundation
import ReachyKit

/// One app, as the widget's configuration picker offers it.
public struct RobotAppEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Robot App")
    public static let defaultQuery = RobotAppQuery()

    /// `RobotApp.id`. This is what the system persists in the widget's saved
    /// configuration and hands back to `entities(for:)`, so it must be the stable
    /// one — the entry point name is not (`RobotApp.matches(installed:)`).
    public let id: String
    /// The installed name, which is what `start-app` takes. Carried on the entity
    /// so a tile can build its intent without another lookup.
    public let name: String
    public let title: String
    public let emoji: String?
    public let gradient: RobotApp.Gradient?
    /// False for an app the robot no longer has, or one this process has never
    /// seen. Such an entity is still returned rather than dropped — see
    /// `RobotAppQuery.entities(for:)`.
    public let isInstalled: Bool

    public init(_ summary: RobotAppSummary, isInstalled: Bool) {
        id = summary.id
        name = summary.name
        title = summary.title
        emoji = summary.emoji
        gradient = summary.gradient
        self.isInstalled = isInstalled
    }

    public var summary: RobotAppSummary {
        RobotAppSummary(id: id, name: name, title: title, emoji: emoji, gradient: gradient)
    }

    public var displayRepresentation: DisplayRepresentation {
        isInstalled
            ? DisplayRepresentation(title: "\(title)")
            : DisplayRepresentation(title: "\(title)", subtitle: "Not installed")
    }
}

/// Where the picker's list comes from.
///
/// Cache first, always. This runs in a process that may have no robot within
/// reach — on cellular, on another network, or with the robot switched off — and
/// a picker that empties itself under those conditions would silently rewrite
/// somebody's widget.
public struct RobotAppQuery: EntityQuery {
    /// Short on purpose, and applied twice — once to the request and once to the
    /// whole fetch (`refreshed()`). The list is a nicety here; the cache is the
    /// answer, and making someone wait for a robot that is not going to answer is
    /// worse than showing them yesterday's list.
    static let refreshTimeout: TimeInterval = 2

    private let cache: RobotAppsCacheStore
    private let robotID: @Sendable () -> String?
    private let fetch: @Sendable () async throws -> RobotAppsCache

    public init() {
        self.init(
            cache: RobotAppsCacheStore(),
            robotID: { RobotIntentTarget.knownRobot?.key },
            fetch: {
                let target = try await RobotIntentTarget.connection(timeout: RobotAppQuery.refreshTimeout)
                let installed = try await target.client.installedApps()
                return RobotAppsCache(
                    robotID: target.robot.key,
                    installed: installed.map(RobotAppSummary.init),
                    takenAt: Date()
                )
            }
        )
    }

    private init(
        cache: RobotAppsCacheStore,
        robotID: @escaping @Sendable () -> String?,
        fetch: @escaping @Sendable () async throws -> RobotAppsCache
    ) {
        self.cache = cache
        self.robotID = robotID
        self.fetch = fetch
    }

    init(
        cache: RobotAppsCacheStore,
        robotID: String,
        fetch: @escaping @Sendable () async throws -> [RobotAppSummary]
    ) {
        self.init(
            cache: cache,
            robotID: { robotID },
            fetch: {
                let installed = try await fetch()
                return RobotAppsCache(robotID: robotID, installed: installed, takenAt: Date())
            }
        )
    }

    /// Resolving a saved configuration. **Never touches the network and never
    /// drops an identifier.**
    ///
    /// Returning fewer entities than were asked for is how the system learns an
    /// app is gone, and it prunes the configuration accordingly — which would turn
    /// one cold launch with an empty cache into a widget the user has to set up
    /// again. So an unknown id comes back as a placeholder built from the id
    /// itself, marked not installed; the tile renders dimmed and the configuration
    /// survives.
    public func entities(for identifiers: [String]) async throws -> [RobotAppEntity] {
        let installed = robotID().flatMap { cache.current(for: $0)?.installed } ?? []
        return identifiers.map { id in
            if let known = installed.first(where: { $0.id == id }) {
                return RobotAppEntity(known, isInstalled: true)
            }
            return RobotAppEntity(Self.placeholder(id: id), isInstalled: false)
        }
    }

    /// Filling the picker. Best effort at a live list, falling back to the cache —
    /// and never throwing, because an empty picker reads as a broken widget.
    ///
    /// An empty answer is treated as a failure rather than as news: it is what a
    /// robot mid-restart reports, and wiping a configured widget's menu on the
    /// strength of it would be the expensive way to be right occasionally.
    public func suggestedEntities() async throws -> [RobotAppEntity] {
        guard let robotID = robotID() else { return [] }
        let cached = cache.current(for: robotID)?.installed ?? []
        guard let fresh = await refreshed(), fresh.robotID == robotID, !fresh.installed.isEmpty else {
            return cached.map { RobotAppEntity($0, isInstalled: true) }
        }
        cache.write(fresh.installed, robotID: robotID, at: fresh.takenAt)
        return fresh.installed.map { RobotAppEntity($0, isInstalled: true) }
    }

    /// The budget that actually ends the wait.
    ///
    /// `timeoutIntervalForRequest` bounds *inactivity*, not total time — a robot
    /// that accepts the connection and then dribbles bytes can hold a request far
    /// past it. Racing the whole fetch is what keeps the picker from sitting empty
    /// while the system waits.
    private func refreshed() async -> RobotAppsCache? {
        await withTaskGroup(of: RobotAppsCache?.self) { group in
            group.addTask { try? await fetch() }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.refreshTimeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// An id with nothing behind it. `RobotApp.id` is `spaceID ?? name`, so the
    /// last path component is the closest thing to a name this can recover.
    private static func placeholder(id: String) -> RobotAppSummary {
        let slug = id.split(separator: "/").last.map(String.init) ?? id
        return RobotAppSummary(id: id, name: slug, title: slug)
    }
}
