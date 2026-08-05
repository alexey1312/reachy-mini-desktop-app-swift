import Foundation
import ReachyKit
@testable import ReachyWidgetUI
import Testing

/// The picker's list, and — more importantly — how a saved configuration is
/// resolved. Getting the second one wrong loses somebody's widget setup without
/// telling them.
@Suite("Robot app query", .timeLimit(.minutes(1)))
struct RobotAppQueryTests {
    private let dance = RobotAppSummary(id: "pollen/dance", name: "dance_party", title: "Dance Party")
    private let faces = RobotAppSummary(id: "pollen/faces", name: "face_tracking", title: "Face Tracking")

    private func store() throws -> RobotAppsCacheStore {
        try RobotAppsCacheStore(
            defaults: #require(UserDefaults(suiteName: "RobotAppQueryTests.\(UUID().uuidString)"))
        )
    }

    private func query(
        _ store: RobotAppsCacheStore,
        fetch: @escaping @Sendable () async throws -> [RobotAppSummary] = { [] }
    ) -> RobotAppQuery {
        RobotAppQuery(cache: store, fetch: fetch)
    }

    // MARK: - Resolving a saved configuration

    @Test("identifiers resolve from the cache, in the order they were asked for")
    func resolvesFromTheCache() async throws {
        let store = try store()
        store.write([dance, faces])

        let resolved = try await query(store).entities(for: [faces.id, dance.id])

        #expect(resolved.map(\.id) == [faces.id, dance.id])
        #expect(resolved.map(\.isInstalled) == [true, true])
        #expect(resolved.first?.name == "face_tracking")
    }

    /// Returning fewer entities than were asked for is how the system learns to
    /// prune a configuration. One cold launch with an empty cache would then cost
    /// the user their whole widget setup, so an unknown id comes back anyway.
    @Test("an unknown identifier still resolves, marked not installed")
    func neverDropsAnIdentifier() async throws {
        let store = try store()
        store.write([dance])

        let resolved = try await query(store).entities(for: [dance.id, "pollen/chess"])

        #expect(resolved.map(\.id) == [dance.id, "pollen/chess"])
        #expect(resolved.last?.isInstalled == false)
        // `RobotApp.id` is `spaceID ?? name`, so the slug is the closest thing to a
        // name there is to recover.
        #expect(resolved.last?.title == "chess")
    }

    @Test("an empty cache still resolves every identifier")
    func resolvesWithNoCacheAtAll() async throws {
        let resolved = try await query(store()).entities(for: [dance.id, faces.id])

        #expect(resolved.count == 2)
        #expect(resolved.allSatisfy { $0.isInstalled == false })
    }

    /// It runs while a timeline is being built and while a configuration is being
    /// restored — both of which happen with no robot in reach.
    @Test("resolving never reaches for the network")
    func resolvesWithoutTheNetwork() async throws {
        let store = try store()
        store.write([dance])
        let reached = Reached()

        _ = try await query(store, fetch: {
            reached.mark()
            return []
        }).entities(for: [dance.id])

        #expect(reached.value == false)
    }

    // MARK: - Filling the picker

    @Test("a live list wins, and is written through to the cache")
    func prefersALiveList() async throws {
        let store = try store()
        store.write([dance])

        let suggested = try await query(store, fetch: { [dance, faces] }).suggestedEntities()

        #expect(suggested.map(\.id) == [dance.id, faces.id])
        #expect(store.current?.installed.count == 2)
    }

    @Test("an unreachable robot falls back to the cache instead of failing")
    func fallsBackToTheCache() async throws {
        let store = try store()
        store.write([dance, faces])

        let suggested = try await query(store, fetch: { throw URLError(.cannotConnectToHost) })
            .suggestedEntities()

        #expect(suggested.map(\.id) == [dance.id, faces.id])
        #expect(store.current?.installed.count == 2)
    }

    @Test("an empty live answer does not wipe the cache")
    func keepsTheCacheOverAnEmptyAnswer() async throws {
        let store = try store()
        store.write([dance])

        let suggested = try await query(store, fetch: { [] }).suggestedEntities()

        #expect(suggested.map(\.id) == [dance.id])
        #expect(store.current?.installed.count == 1)
    }

    /// The fallback and the success path end in the same shape — a list of
    /// entities — so only the duration tells them apart (project rule 7). A query
    /// that waited out a hanging robot would leave the picker empty for as long as
    /// the system is willing to wait, which reads as a broken widget.
    @Test("a robot that never answers does not hold the picker open")
    func doesNotWaitOutAHangingRobot() async throws {
        let store = try store()
        store.write([dance])

        let start = ContinuousClock.now
        let suggested = try await query(store, fetch: {
            try await Task.sleep(for: .seconds(30))
            return []
        }).suggestedEntities()
        let elapsed = ContinuousClock.now - start

        #expect(suggested.map(\.id) == [dance.id])
        #expect(elapsed < .seconds(10))
    }
}

/// A flag a `@Sendable` closure can set from anywhere.
private final class Reached: @unchecked Sendable {
    private let lock = NSLock()
    private var reached = false

    var value: Bool {
        lock.withLock { reached }
    }

    func mark() {
        lock.withLock { reached = true }
    }
}
