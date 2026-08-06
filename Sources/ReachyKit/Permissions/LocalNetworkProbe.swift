import Foundation
import Network

/// Whether this app may use the local network — the one permission with no API to ask.
///
/// There is no `authorizationStatus` for it, so the answer has to be *observed*: start
/// a browser and watch what becomes of it. The two definitive signals are asymmetric,
/// and getting either one wrong is how this app would lie about it.
///
/// - **`PolicyDenied`, or its raw `-65570`, means denied.** Nothing else produces it.
/// - **A browse result arriving means granted.** A peer cannot be seen without the grant.
///
/// **`NWBrowser` reaching `.ready` proves nothing.** It gets there while the system
/// prompt is still on screen, before the user has answered anything, so reading it as a
/// grant would paint "Allowed" over an open question — the mirror image of the false
/// denial `.claude/rules/networking.md` warns about. `.ready`, an empty result set and
/// the timeout therefore all mean the same thing here: not known yet.
///
/// That leaves one honest gap, and it is not a bug to be fixed later by loosening the
/// rule: a *granted* permission on a network with no robot on it also resolves
/// `.undetermined`, because nothing ever arrives to prove otherwise. The screen says as
/// much in words. The only way to close it is to publish a service and find oneself,
/// which means advertising this phone under a Bonjour type — and it must never be
/// `_reachy-mini._tcp`, or the app would list itself as a robot.
public enum LocalNetworkProbe {
    /// What the probe watches. Two channels, because the browser's state and its results
    /// answer different halves of the question — one can only ever say "no", the other
    /// only ever "yes".
    public enum Event: Sendable, Equatable {
        /// A stringified `NWBrowser.State`. Stringified because the refusal is not
        /// exposed as a case — see `looksPolicyDenied`.
        case state(String)
        case results(count: Int)
    }

    /// The whole rule, as a value mapping. `nil` means "keep waiting", not "unknown".
    public static func classify(_ event: Event) -> PermissionState? {
        switch event {
        case let .state(description): looksPolicyDenied(description) ? .denied : nil
        case let .results(count): count > 0 ? .granted : nil
        }
    }

    /// `NWBrowser` surfaces a refusal as a `.waiting` state carrying
    /// `kDNSServiceErr_PolicyDenied` and offers no typed way to read it back out. Both
    /// spellings turn up depending on the OS, so both are matched.
    ///
    /// `RobotBrowser.permissionLooksDenied` reads the same rule off its stored states;
    /// this is the one copy of it.
    public static func looksPolicyDenied(_ state: String) -> Bool {
        state.contains("PolicyDenied") || state.contains("-65570")
    }

    /// Runs a browser until it proves the answer either way, or until `timeout`.
    ///
    /// **Starting a browser is what raises the prompt**, so this is only ever called
    /// from an explicit user action — never from a screen appearing.
    public static func resolve(
        timeout: Duration = .seconds(4),
        events: @Sendable @escaping () -> AsyncStream<Event> = LocalNetworkProbe.liveEvents
    ) async -> PermissionState {
        await withTaskGroup(of: PermissionState?.self) { group in
            group.addTask {
                for await event in events() {
                    if let resolved = classify(event) { return resolved }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .undetermined
        }
    }

    /// One browser, on the primary service type only: the legacy `_http._tcp` adds
    /// nothing to a permission answer and would double the adverts for no gain.
    ///
    /// Built with `makeStream` rather than the `AsyncStream { continuation in … }`
    /// builder on purpose. The root `CLAUDE.md` records a closure nested inside that
    /// builder and capturing the escaping continuation sending `ClosureLifetimeFixup`
    /// into a dominator walk it does not return from — twenty minutes of one core, no
    /// diagnostic, and `-Onone` does not avoid it. Two handler assignments are exactly
    /// that shape. `makeStream` has no builder closure to nest inside.
    public static func liveEvents() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream(of: Event.self)
        let browser = NWBrowser(
            for: .bonjour(type: RobotBrowser.serviceTypes[0], domain: nil),
            using: .tcp
        )
        browser.stateUpdateHandler = { state in
            continuation.yield(.state("\(state)"))
        }
        browser.browseResultsChangedHandler = { results, _ in
            continuation.yield(.results(count: results.count))
        }
        // Whoever stops reading — a resolved answer, the timeout, a cancelled screen —
        // is what tears the browser down. There is no other owner.
        continuation.onTermination = { _ in browser.cancel() }
        browser.start(queue: .global())
        return stream
    }
}
