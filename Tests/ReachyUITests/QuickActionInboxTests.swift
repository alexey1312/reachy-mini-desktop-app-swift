@testable import ReachyUI
import Testing

/// The inbox is one value with one job, and the job is easy to get subtly wrong:
/// SwiftUI notices a *change*, so a command that looks identical to the last one
/// has to arrive as a different value or it never runs.
@MainActor
@Suite("Home Screen quick actions")
struct QuickActionInboxTests {
    @Test("the same command twice in a row is two events")
    func distinguishesRepeatedTaps() {
        let inbox = QuickActionInbox()

        inbox.receive(type: "wake")
        let first = inbox.pending
        inbox.receive(type: "wake")

        #expect(first?.action == .wake)
        #expect(inbox.pending?.action == .wake)
        #expect(inbox.pending != first)
    }

    @Test("reading a command takes it")
    func clearsOnRead() {
        let inbox = QuickActionInbox()
        inbox.receive(type: "power-off")

        #expect(inbox.take() == .powerOff)
        #expect(inbox.pending == nil)
        #expect(inbox.take() == nil)
    }

    /// The boolean is what UIKit's `performActionFor` completion handler wants, and
    /// an identifier this app does not own must not leave a command queued.
    @Test("an unknown identifier is refused and queues nothing")
    func refusesAnUnknownIdentifier() {
        let inbox = QuickActionInbox()

        #expect(inbox.receive(type: "com.example.other") == false)
        #expect(inbox.pending == nil)
    }

    /// The raw values are the `UIApplicationShortcutItem` types installed on the
    /// Home Screen. Changing one silently orphans every icon already on a device.
    @Test("the identifiers are the ones the Home Screen holds")
    func pinsTheIdentifiers() {
        #expect(ReachyQuickAction.allCases.map(\.rawValue) == ["wake", "sleep", "power-off"])
    }
}
