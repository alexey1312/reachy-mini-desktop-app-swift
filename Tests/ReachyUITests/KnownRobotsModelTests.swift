import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

@MainActor
@Suite("KnownRobotsModel", .timeLimit(.minutes(1)))
struct KnownRobotsModelTests {
    private func makeStore() throws -> KnownRobotStore {
        let defaults = try #require(UserDefaults(suiteName: "KnownRobotsModelTests.\(UUID().uuidString)"))
        let store = KnownRobotStore(defaults: defaults)
        store.remember(
            identity: RobotIdentity(hardwareID: "hw-1", name: "reachy_mini"),
            address: RobotAddress(host: "10.0.0.9"),
            at: Date(timeIntervalSince1970: 100)
        )
        return store
    }

    @Test("a robot answering its daemon shows as reachable")
    func reachable() async throws {
        let model = try KnownRobotsModel(store: makeStore(), interval: .milliseconds(20)) { _ in true }

        model.start()
        await waitUntil("the robot is reachable") { model.entries.first?.status == .reachable }
        model.stop()
    }

    @Test("a robot that answers nothing shows as not responding")
    func unreachable() async throws {
        let model = try KnownRobotsModel(store: makeStore(), interval: .milliseconds(20)) { _ in false }

        model.start()
        await waitUntil("the robot is unreachable") { model.entries.first?.status == .unreachable }
        model.stop()
    }

    @Test("a robot found over Bonjour needs no probe to count as present")
    func discoveredCountsAsReachable() throws {
        // The probe never answers, so only the discovery result can move this off `.checking`.
        let model = try KnownRobotsModel(store: makeStore(), interval: .seconds(60)) { _ in
            try? await Task.sleep(for: .seconds(60))
            return false
        }

        model.updateDiscovered(["hw-1"])

        #expect(model.entries.first?.status == .reachable)
    }

    @Test("forgetting a robot drops it from the list and from storage")
    func forgets() throws {
        let store = try makeStore()
        let model = KnownRobotsModel(store: store, interval: .seconds(60)) { _ in true }

        model.forget("hw-1")

        #expect(model.entries.isEmpty)
        #expect(store.all.isEmpty)
    }
}

/// Polls rather than sleeping: the suites are `@MainActor` and a loaded runner starves
/// them, so a fixed wait before an assertion is a flake in waiting (rule 7).
@MainActor
private func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(10),
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("timed out waiting until \(description)", sourceLocation: sourceLocation)
}
