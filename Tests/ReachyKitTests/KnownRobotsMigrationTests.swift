import Foundation
@testable import ReachyKit
import Testing

/// Moving storage into an app group is invisible to the user only if what they
/// already have moves with it: a robot list that reappears empty after an update
/// reads as data loss, whatever the release notes say.
@Suite("Known robots migration")
struct KnownRobotsMigrationTests {
    private func suite(_ label: String) throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "KnownRobotsMigrationTests.\(label).\(UUID().uuidString)"))
    }

    private func store(_ defaults: UserDefaults) -> KnownRobotStore {
        KnownRobotStore(defaults: defaults)
    }

    @Test("an existing installation's robots arrive in the shared suite")
    func carriesRobotsOver() throws {
        let legacy = try suite("legacy")
        let shared = try suite("shared")
        store(legacy).remember(
            identity: RobotIdentity(hardwareID: "b68ff6bbe47f0608", name: "kitchen"),
            address: RobotAddress(host: "192.168.1.42")
        )
        legacy.set(true, forKey: KnownRobots.onboardingKey)

        KnownRobots.migrate(from: legacy, to: shared)

        #expect(store(shared).all.map(\.name) == ["kitchen"])
        #expect(store(shared).lastAddress == nil)
        #expect(shared.bool(forKey: KnownRobots.onboardingKey))
    }

    /// The address the manual field offers is stored separately from the robot
    /// list, and losing it sends the user back to typing an IP.
    @Test("the last address comes over too")
    func carriesTheLastAddress() throws {
        let legacy = try suite("legacy")
        let shared = try suite("shared")
        store(legacy).lastAddress = RobotAddress(host: "10.42.0.1")

        KnownRobots.migrate(from: legacy, to: shared)

        #expect(store(shared).lastAddress == RobotAddress(host: "10.42.0.1"))
    }

    /// Migration runs on every launch, and by the second one the shared suite is
    /// the truth. Copying again would resurrect robots the user has since removed.
    @Test("a second migration leaves the shared suite alone")
    func doesNotRunTwice() throws {
        let legacy = try suite("legacy")
        let shared = try suite("shared")
        store(legacy).remember(
            identity: RobotIdentity(hardwareID: "b68ff6bbe47f0608", name: "kitchen"),
            address: RobotAddress(host: "192.168.1.42")
        )

        KnownRobots.migrate(from: legacy, to: shared)
        store(shared).forget("b68ff6bbe47f0608")
        KnownRobots.migrate(from: legacy, to: shared)

        #expect(store(shared).all.isEmpty)
    }

    /// Copied, not moved. A user who downgrades still has their robots, and
    /// nothing is destroyed to save a few bytes.
    @Test("the old storage is left untouched")
    func leavesLegacyIntact() throws {
        let legacy = try suite("legacy")
        let shared = try suite("shared")
        store(legacy).remember(
            identity: RobotIdentity(hardwareID: "b68ff6bbe47f0608", name: "kitchen"),
            address: RobotAddress(host: "192.168.1.42")
        )

        KnownRobots.migrate(from: legacy, to: shared)

        #expect(store(legacy).all.map(\.name) == ["kitchen"])
    }

    /// No entitlement, no group to open — a fork that has not set one up, and
    /// every unit test. Falling back keeps the app working on its own storage
    /// instead of losing every setting it has.
    @Test("without an app group the shared defaults are the standard ones")
    func fallsBackToStandardDefaults() {
        #expect(KnownRobots.defaults === UserDefaults.standard)
    }

    /// Nothing to carry is the common case — a fresh install — and it must not
    /// write a robot list of its own or mark anything as present.
    @Test("a fresh install migrates nothing and stays empty")
    func handlesAFreshInstall() throws {
        let legacy = try suite("legacy")
        let shared = try suite("shared")

        KnownRobots.migrate(from: legacy, to: shared)

        #expect(store(shared).all.isEmpty)
        #expect(store(shared).lastAddress == nil)
        #expect(shared.bool(forKey: KnownRobots.onboardingKey) == false)
    }
}
