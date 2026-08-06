import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

/// Project rule 7 says tests wait on conditions rather than durations, and it names
/// its own exception: where two paths end in the same state and differ only in how
/// long they take, the duration *is* the assertion. That is this whole suite. A held
/// stage and an immediate one both end with `displayed == phase`; asserting on the
/// value alone passes either way, and the bug — a dwell that silently stopped
/// holding — would sail through with nothing but `test_time` quietly shrunk.
///
/// So spans are measured on a `ContinuousClock` and bounded an order of magnitude
/// apart: tens of milliseconds against hundreds. A loaded runner cannot cross that.
/// Each bound below was checked by mutating the branch it covers and watching the
/// test go red before being trusted.
@MainActor
@Suite("ConnectProgressModel", .timeLimit(.minutes(1)))
struct ConnectProgressModelTests {
    private let identity = RobotIdentity.preview

    @Test("a zero dwell shows every phase synchronously and never holds the gate")
    func zeroDwellIsTransparent() {
        let model = ConnectProgressModel(dwell: .zero)

        model.observe(.connecting(.handshaking))
        #expect(model.displayed == .connecting(.handshaking))
        model.observe(.connecting(.checkingBackend(identity)))
        #expect(model.displayed == .connecting(.checkingBackend(identity)))
        model.observe(.connected(identity))
        #expect(model.displayed == .connected(identity))
        #expect(model.holdsGate == false)
    }

    @Test("the first phase of an attempt is shown at once")
    func firstPhaseIsImmediate() {
        let model = ConnectProgressModel(dwell: .milliseconds(300))

        model.observe(.connecting(.handshaking))

        // Nothing was on screen to be displaced, so there is no floor to respect.
        #expect(model.displayed == .connecting(.handshaking))
    }

    @Test("a stage that resolves instantly is still held on screen")
    func fastStagesAreHeld() async {
        let model = ConnectProgressModel(dwell: .milliseconds(300))
        model.observe(.connecting(.handshaking))

        let elapsed = await ContinuousClock().measure {
            model.observe(.connecting(.checkingBackend(identity)))
            await waitUntil("the second stage is shown") {
                model.displayed == .connecting(.checkingBackend(identity))
            }
        }

        // Without the floor this resolves in the same tick — microseconds, not 200 ms.
        #expect(elapsed > .milliseconds(200))
    }

    @Test("every stage gets its turn rather than the newest one winning")
    func middleStageIsNotSkipped() async {
        let model = ConnectProgressModel(dwell: .milliseconds(120))
        model.observe(.connecting(.handshaking))

        // Both arrive while the first stage still owns the screen. Newest-wins would
        // drop the middle one entirely, which is what makes the rail's second node
        // light up out of nowhere.
        model.observe(.connecting(.checkingBackend(identity)))
        model.observe(.connected(identity))

        await waitUntil("the middle stage is shown") {
            model.displayed == .connecting(.checkingBackend(identity))
        }
        await waitUntil("the attempt finishes") { model.displayed == .connected(identity) }
    }

    @Test("the gate is held past the final frame and then released")
    func gateOutlivesTheLastStage() async {
        let model = ConnectProgressModel(dwell: .milliseconds(150))
        model.observe(.connecting(.handshaking))
        model.observe(.connected(identity))

        await waitUntil("the connected frame is shown") { model.displayed == .connected(identity) }
        // The bug this catches is subtle and was in the first draft: releasing the
        // gate on the same tick the checkmarks are drawn means the root replaces the
        // gate before a single frame renders them.
        #expect(model.holdsGate)

        await waitUntil("the gate is released") { model.holdsGate == false }
    }

    @Test("a failure is shown without waiting and drops what was queued")
    func failureBypassesTheDwell() {
        let model = ConnectProgressModel(dwell: .seconds(30))
        model.observe(.connecting(.handshaking))
        model.observe(.connecting(.checkingBackend(identity)))

        let failure = RobotSession.ConnectionPhase.connecting(.failed(.connect, message: "no route"))
        let elapsed = ContinuousClock().measure { model.observe(failure) }

        // Here the three assertions catch the wrong branch together rather than the
        // span carrying it alone: queued behind a 30 s dwell the failure is not
        // `displayed` yet either, and `holdsGate` is still set. Measured against the
        // mutant — `showsWithoutWaiting` returning false — which turns two of the
        // three red.
        #expect(elapsed < .milliseconds(100))
        #expect(model.displayed == failure)
        #expect(model.holdsGate == false)
    }

    @Test("a cancelled attempt releases the gate rather than stranding the reader")
    func resetReleasesTheGate() {
        let model = ConnectProgressModel(dwell: .seconds(30))
        model.observe(.connecting(.handshaking))
        model.observe(.connecting(.checkingBackend(identity)))
        #expect(model.holdsGate)

        model.reset()

        #expect(model.displayed == .idle)
        #expect(model.holdsGate == false)
    }

    @Test("the ceiling releases the gate however much was queued behind it")
    func maxHoldBoundsTheWholeWalk() async {
        // A dwell that would take three stages well past a second, against a ceiling
        // that cuts in first. The point is that the bound does not depend on how many
        // phases happened to arrive.
        let model = ConnectProgressModel(dwell: .milliseconds(400), maxHold: .milliseconds(200))
        model.observe(.connecting(.handshaking))

        let elapsed = await ContinuousClock().measure {
            model.observe(.connecting(.checkingBackend(identity)))
            model.observe(.connected(identity))
            await waitUntil("the gate is released") { model.holdsGate == false }
        }

        #expect(model.displayed == .connected(identity))
        #expect(elapsed < .milliseconds(1200))
    }
}

/// `@MainActor` unlike the copies beside it: every condition here closes over a
/// main-actor model, and a nonisolated parameter makes that closure a value being
/// sent across actors — `sending value of non-Sendable type '() -> Bool'`.
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
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out waiting until \(description)", sourceLocation: sourceLocation)
}
