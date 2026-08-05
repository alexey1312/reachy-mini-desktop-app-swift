import Foundation
@testable import ReachyKit
import Testing

/// The other half of the `type` discriminator.
///
/// A reply never names a `type` and a broadcast always does, which is how
/// `RemoteControlChannel` tells them apart. That rule was implemented as a filter
/// long before anything could subscribe — every typed message was simply dropped —
/// so these cover the fan-out that turns it into a delivery route.
@Suite("Remote control channel broadcasts", .timeLimit(.minutes(1)))
struct RemoteControlChannelBroadcastTests {
    private func channel(
        timeout: Duration = .seconds(5),
        openingTimeout: Duration = .seconds(5)
    ) -> (RemoteControlChannel, FakeDataChannel) {
        let fake = FakeDataChannel()
        return (
            RemoteControlChannel(channel: fake, timeout: timeout, openingTimeout: openingTimeout),
            fake
        )
    }

    /// The other half of the `type` discriminator. Until this existed it was only
    /// ever used to drop a message.
    @Test("a broadcast reaches a subscriber of its type")
    func deliversABroadcastToItsSubscriber() async throws {
        let (control, fake) = channel()
        var lines = await control.broadcasts(ofType: "log_line").makeAsyncIterator()
        while !fake.isListening {
            await Task.yield()
        }

        fake.emit(#"{"type":"log_line","timestamp":"2026-08-05T09:12:01+0000","line":"starting"}"#)

        let data = try #require(await lines.next())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["line"] as? String == "starting")
    }

    /// Joint positions arrive at 50 Hz on the same channel as the journal. A
    /// console subscribed to one must never be handed the other.
    @Test("a broadcast of another type is not delivered")
    func ignoresABroadcastOfAnotherType() async throws {
        let (control, fake) = channel()
        var lines = await control.broadcasts(ofType: "log_line").makeAsyncIterator()
        while !fake.isListening {
            await Task.yield()
        }

        fake.emit(#"{"type":"joint_positions","positions":[0,0]}"#)
        fake.emit(#"{"type":"log_line","timestamp":"t","line":"wanted"}"#)

        let data = try #require(await lines.next())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["line"] as? String == "wanted")
    }

    /// A reply is not a broadcast: it names no `type`, and a subscriber must not
    /// see somebody else's answer.
    @Test("a reply is never delivered to a broadcast subscriber")
    func doesNotDeliverRepliesToSubscribers() async throws {
        let (control, fake) = channel()
        var replies = await control.broadcasts(ofType: "log_line").makeAsyncIterator()
        while !fake.isListening {
            await Task.yield()
        }

        fake.emit(#"{"status":"ok","command":"wake_up","completed":true}"#)
        fake.emit(#"{"version":"1.9.0"}"#)
        fake.emit(#"{"type":"log_line","timestamp":"t","line":"the only one"}"#)

        let data = try #require(await replies.next())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["line"] as? String == "the only one")
    }

    /// The session ending is the subscription ending. A log console left frozen
    /// with no explanation is the failure this prevents.
    @Test("closing the channel finishes open subscriptions")
    func finishesSubscriptionsWhenTheChannelCloses() async {
        let (control, fake) = channel()
        let stream = await control.broadcasts(ofType: "log_line")
        while !fake.isListening {
            await Task.yield()
        }

        fake.close()

        var received = 0
        for await _ in stream {
            received += 1
        }
        #expect(received == 0)
    }

    /// `subscribe_logs` is answered with nothing at all, so a subscriber has to be
    /// able to start the reader without a command ever having been performed.
    @Test("subscribing starts reading on its own")
    func subscribingStartsTheReader() async {
        let (control, fake) = channel()

        _ = await control.broadcasts(ofType: "log_line")

        while !fake.isListening {
            await Task.yield()
        }
        #expect(fake.isListening)
    }

    /// The whole point of `send`: `subscribe_logs` acknowledges nothing, so a
    /// `perform` would spend its entire budget and then misreport an obedient
    /// robot. Both paths end in the command reaching the wire — only the elapsed
    /// time tells a fire-and-forget from a wait that timed out, so it is what is
    /// asserted, loosely enough that a loaded runner cannot cross it.
    @Test("a sent command does not wait for an answer")
    func sendDoesNotWaitForAReply() async throws {
        let (control, fake) = channel(timeout: .seconds(30), openingTimeout: .seconds(30))
        let clock = ContinuousClock()
        let started = clock.now

        try await control.send("subscribe_logs")

        #expect(clock.now - started < .seconds(5))
        let sent = try #require(fake.sent.first)
        let object = try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any]
        #expect(object?["type"] as? String == "subscribe_logs")
    }
}
