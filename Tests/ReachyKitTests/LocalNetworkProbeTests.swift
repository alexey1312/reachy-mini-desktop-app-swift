@testable import ReachyKit
import Testing

/// The probe is the one permission with no API behind it, so the rule it applies *is*
/// the feature. Every case here is a value, not a duration: the timeout branch returns
/// `.undetermined` where the others return something else, so mutating any branch turns
/// a test red on the answer alone.
@Suite("LocalNetworkProbe", .timeLimit(.minutes(1)))
struct LocalNetworkProbeTests {
    private typealias Events = @Sendable () -> AsyncStream<LocalNetworkProbe.Event>

    /// Built with `makeStream` rather than the `AsyncStream { … }` builder, for the
    /// reason `LocalNetworkProbe.liveEvents` gives: a closure nested inside that builder
    /// and capturing the continuation — `forEach` would be one — is the shape the root
    /// `CLAUDE.md` records hanging the compiler for twenty minutes with no diagnostic.
    private static func stream(_ events: [LocalNetworkProbe.Event]) -> Events {
        {
            let (stream, continuation) = AsyncStream<LocalNetworkProbe.Event>.makeStream()
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
            return stream
        }
    }

    @Test("policy denial is recognized in both spellings")
    func denialSpellings() {
        #expect(LocalNetworkProbe.looksPolicyDenied("waiting(PolicyDenied)"))
        #expect(LocalNetworkProbe.looksPolicyDenied("waiting(-65570: PolicyDenied)"))
        #expect(LocalNetworkProbe.looksPolicyDenied("DNS error -65570"))
        #expect(!LocalNetworkProbe.looksPolicyDenied("ready"))
    }

    @Test("only a refusal and an arriving result decide anything")
    func classification() {
        #expect(LocalNetworkProbe.classify(.state("waiting(-65570: PolicyDenied)")) == .denied)
        #expect(LocalNetworkProbe.classify(.results(count: 2)) == .granted)
        // The load-bearing one. `.ready` arrives while the system prompt is still on
        // screen, so reading it as a grant would claim consent nobody has given yet.
        #expect(LocalNetworkProbe.classify(.state("ready")) == nil)
        #expect(LocalNetworkProbe.classify(.state("setup")) == nil)
        #expect(LocalNetworkProbe.classify(.results(count: 0)) == nil)
    }

    @Test("a refusal resolves to denied")
    func refusalResolves() async {
        let state = await LocalNetworkProbe.resolve(events: Self.stream([.state("waiting(-65570: PolicyDenied)")]))
        #expect(state == .denied)
    }

    @Test("a robot answering proves the grant")
    func resultResolves() async {
        let state = await LocalNetworkProbe.resolve(events: Self.stream([.state("ready"), .results(count: 1)]))
        #expect(state == .granted)
    }

    @Test("a ready browser that finds nothing stays unknown rather than becoming a grant")
    func readyIsNotAGrant() async {
        let state = await LocalNetworkProbe.resolve(events: Self.stream([.state("ready"), .results(count: 0)]))
        #expect(state == .undetermined)
    }

    @Test("a prompt nobody answers times out as unknown, never as a refusal")
    func timeoutIsNotARefusal() async {
        // Never finishes — the stream owns the continuation and nothing yields — so only
        // the timeout can end this. The budget is injected and short; nothing here
        // asserts on how long it took, only on the answer.
        let hanging: Events = { AsyncStream { _ in } }
        let state = await LocalNetworkProbe.resolve(timeout: .milliseconds(50), events: hanging)
        #expect(state == .undetermined)
    }
}
