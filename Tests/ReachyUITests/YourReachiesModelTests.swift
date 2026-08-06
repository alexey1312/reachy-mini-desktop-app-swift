import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

/// Hands out scripted answers and counts how often it was asked, so a test can
/// show that a signed-out account never reaches central at all.
private final class ListingDouble: CentralRobotListing, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<[CentralRobot], any Error>]
    private var calls = 0

    init(_ answers: [Result<[CentralRobot], any Error>]) {
        self.answers = answers
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func robots() async throws -> [CentralRobot] {
        try next().get()
    }

    /// Repeats the last answer forever, so a test only scripts the turns it cares
    /// about.
    private func next() -> Result<[CentralRobot], any Error> {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return answers.count > 1 ? answers.removeFirst() : answers[0]
    }
}

/// A listing that answers only when the test says so, and in the order the test
/// chooses.
///
/// Ordering two in-flight requests by sleeping for different durations is the flake
/// project rule 7 warns about; this waits on the condition instead — a call having
/// arrived, and then an answer being released.
private actor GatedListing: CentralRobotListing {
    private(set) var callCount = 0
    private var calls: [CheckedContinuation<[CentralRobot], any Error>] = []
    private var arrivals: [CheckedContinuation<Void, Never>] = []

    func robots() async throws -> [CentralRobot] {
        try await withCheckedThrowingContinuation { continuation in
            callCount += 1
            calls.append(continuation)
            for arrival in arrivals {
                arrival.resume()
            }
            arrivals = []
        }
    }

    /// Returns once `count` calls have arrived, so a test never releases an answer
    /// to a request that has not been made yet.
    func waitForCalls(_ count: Int) async {
        while callCount < count {
            await withCheckedContinuation { arrivals.append($0) }
        }
    }

    /// Answers the call that arrived `index`-th, counting from zero.
    func answer(_ index: Int, with robots: [CentralRobot]) {
        calls[index].resume(returning: robots)
    }
}

/// Whether the account is signed in, as something a test can flip after the model
/// has already taken the closure that reads it.
@MainActor
private final class SignedInFlag {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

@MainActor
@Suite("Your Reachies", .timeLimit(.minutes(1)))
struct YourReachiesModelTests {
    /// Decoded rather than built: `CentralRobot` has no memberwise initialiser on
    /// purpose, and this exercises the shape central actually sends.
    private static func robots(_ json: String) throws -> [CentralRobot] {
        try JSONDecoder().decode([CentralRobot].self, from: Data(json.utf8))
    }

    private func model(
        _ answers: [Result<[CentralRobot], any Error>],
        signedIn: Bool = true
    ) -> (YourReachiesModel, ListingDouble) {
        let listing = ListingDouble(answers)
        return (YourReachiesModel(listing: listing, isSignedIn: { signedIn }), listing)
    }

    @Test("a signed-in account starts in the content-loading state")
    func initialContentLoading() {
        let (model, _) = model([.success([])])

        #expect(model.isContentLoading)
    }

    @Test("a signed-out account starts at sign-in instead of a loader")
    func signedOutIsNotContentLoading() {
        let (model, _) = model([.success([])], signedIn: false)

        #expect(!model.isContentLoading)
    }

    /// Central authenticates every call with the user's own token. Without one
    /// there is nothing to ask with, and asking would only spend a round trip to
    /// be told so.
    @Test("a signed-out account never reaches central")
    func staysPutWhenSignedOut() async {
        let (model, listing) = model([.success([])], signedIn: false)

        await model.load()

        #expect(model.state == .signedOut)
        #expect(listing.callCount == 0)
    }

    /// Not an error: the account is fine, the robots are simply off.
    @Test("an empty answer reads as nothing online rather than a failure")
    func reportsNothingOnline() async {
        let (model, _) = model([.success([])])

        await model.load()

        #expect(model.state == .empty)
        #expect(!model.isContentLoading)
    }

    @Test("robots central lists come back to the screen")
    func listsRobots() async throws {
        let robots = try Self.robots(#"""
        [{"peerId":"p1","robotName":"kitchen","meta":{"name":"kitchen","hardware_id":"abc"}}]
        """#)
        let (model, _) = model([.success(robots)])

        await model.load()

        #expect(model.state == .listed(robots))
    }

    /// A robot someone else is using is still worth showing — it is online, and
    /// naming what holds it is the difference between "busy" and "broken".
    @Test("a busy robot is listed with whatever is holding it")
    func listsBusyRobots() async throws {
        let robots = try Self.robots(#"""
        [{"peerId":"p1","robotName":"kitchen","busy":true,"activeApp":"Hand Tracker"}]
        """#)
        let (model, _) = model([.success(robots)])

        await model.load()

        #expect(model.state == .listed(robots))
        #expect(robots.first?.activeApp == "Hand Tracker")
    }

    /// Central refusing the token is not a transient failure — the same token
    /// will be refused again, so the screen has to say "sign in", not "retry".
    @Test("a refused token asks for a new sign-in rather than a retry")
    func reportsARefusedToken() async {
        let (model, _) = model([.failure(CentralRelayClient.Failure.unauthorized)])

        await model.load()

        #expect(model.state == .needsSignIn)
    }

    /// 1200 requests a minute per token, and retrying at once turns a limit into
    /// a ban — so this one says to wait, and it says so as a failure the user can
    /// act on.
    @Test("a rate limit is reported as such")
    func reportsARateLimit() async {
        let (model, _) = model([.failure(CentralRelayClient.Failure.rateLimited)])

        await model.load()

        guard case let .failed(reason) = model.state else {
            Issue.record("expected a failure, got \(model.state)")
            return
        }
        #expect(reason.localizedCaseInsensitiveContains("too many"))
    }

    /// A refresh that fails must not blank a list the user is looking at: the
    /// robots did not go away, the request did.
    @Test("a failed refresh keeps the robots already on screen")
    func keepsRobotsThroughAFailedRefresh() async throws {
        let robots = try Self.robots(#"[{"peerId":"p1","robotName":"kitchen"}]"#)
        let (model, _) = model([
            .success(robots),
            .failure(CentralRelayClient.Failure.http(503)),
        ])

        await model.load()
        await model.refresh()

        #expect(model.state == .listed(robots))
        #expect(model.lastRefreshError != nil)
        #expect(!model.isContentLoading)
    }

    /// The one signal a user can act on directly, and the only place this app can
    /// tell them their session lapsed before they try to use a robot.
    @Test("signing out drops back to the signed-out state")
    func returnsToSignedOut() async throws {
        let robots = try Self.robots(#"[{"peerId":"p1"}]"#)
        // A box rather than a captured `var`: the model holds this closure for its
        // lifetime, and a mutable local captured by an escaping one is read through
        // a shared box the compiler warns about today and rejects tomorrow.
        let signedIn = SignedInFlag(true)
        let listing = ListingDouble([.success(robots)])
        let model = YourReachiesModel(listing: listing, isSignedIn: { signedIn.value })

        await model.load()
        #expect(model.state == .listed(robots))

        signedIn.value = false
        await model.refresh()

        #expect(model.state == .signedOut)
    }

    /// The screen's `.task` and a pull-to-refresh land on the same model, and
    /// central answers them in whatever order it likes. The older answer arriving
    /// second must not win: that is a list of robots turning into "none online" a
    /// moment after it appeared, for no reason the user can see.
    @Test("a superseded request never writes back over a newer answer")
    func dropsASupersededAnswer() async throws {
        let robots = try Self.robots(#"[{"peerId":"p1","robotName":"kitchen"}]"#)
        let listing = GatedListing()
        let model = YourReachiesModel(listing: listing, isSignedIn: { true })

        let first = Task { await model.load() }
        await listing.waitForCalls(1)
        let second = Task { await model.refresh() }
        await listing.waitForCalls(2)

        await listing.answer(1, with: robots)
        await second.value
        // The first request answers last, from a sweep that ran before the robot
        // registered with central.
        await listing.answer(0, with: [])
        await first.value

        #expect(model.state == .listed(robots))
    }

    /// Signing out is a decision the answer in flight knows nothing about.
    @Test("an answer that lands after signing out does not repopulate the list")
    func dropsAnAnswerFromASignedOutAccount() async throws {
        let robots = try Self.robots(#"[{"peerId":"p1","robotName":"kitchen"}]"#)
        let signedIn = SignedInFlag(true)
        let listing = GatedListing()
        let model = YourReachiesModel(listing: listing, isSignedIn: { signedIn.value })

        let load = Task { await model.load() }
        await listing.waitForCalls(1)
        signedIn.value = false
        model.accountChanged()
        await listing.answer(0, with: robots)
        await load.value

        #expect(model.state == .signedOut)
    }

    /// The model outlives the sheet now, so the account boundary must explicitly
    /// discard rows that belong to the previous owner. A failed request for the
    /// next account must not preserve those rows as though it were a refresh.
    @Test("changing accounts clears the previous account's robots")
    func changingAccountsClearsRobots() async throws {
        let robots = try Self.robots(#"[{"peerId":"p1","robotName":"kitchen"}]"#)
        let signedIn = SignedInFlag(true)
        let listing = ListingDouble([
            .success(robots),
            .failure(CentralRelayClient.Failure.http(503)),
        ])
        let model = YourReachiesModel(listing: listing, isSignedIn: { signedIn.value })

        await model.load()
        #expect(model.state == .listed(robots))

        signedIn.value = false
        model.accountChanged()
        #expect(model.state == .signedOut)

        signedIn.value = true
        model.accountChanged()
        await model.load()

        #expect(!model.state.hasRobots)
        #expect(model.lastRefreshError == nil)
    }

    /// `.task` runs once per presentation, but nothing stops a second `load()`
    /// arriving while the first is still out. Central allows 1200 requests a minute
    /// per token and a duplicate buys nothing.
    @Test("a second load while one is in flight asks central once")
    func loadsOnceWhileInFlight() async {
        let listing = GatedListing()
        let model = YourReachiesModel(listing: listing, isSignedIn: { true })

        let load = Task { await model.load() }
        await listing.waitForCalls(1)
        await model.load()
        let callCount = await listing.callCount

        #expect(callCount == 1)

        await listing.answer(0, with: [])
        await load.value
        #expect(model.state == .empty)
    }
}
