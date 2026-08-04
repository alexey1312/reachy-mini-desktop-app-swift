import Foundation

/// Tracks the robot's PIN session and its wrong-PIN throttle, which have different
/// lifetimes and are easy to conflate.
///
/// The session is a 300 s window the robot opens on a correct `PIN_…` and **drops the
/// moment BLE disconnects**. The throttle is robot-global, counts wrong attempts, and
/// **survives a disconnect** — during a lockout the robot does not even compare the
/// PIN, so a correct one still fails. Reconnecting therefore clears the permission but
/// not the penalty.
public struct BLEPinSession: Equatable, Sendable {
    /// `SESSION_TTL_S` in `bluetooth_service.py`.
    public static let ttl: Duration = .seconds(300)
    /// The robot's PIN is the last five characters of the Pollen audio device's USB serial
    /// (`38fb:1001`), compared verbatim — not necessarily digits, and never case-folded.
    /// Upstream prints that serial on the robot. With no audio board attached the daemon
    /// falls back to a fixed `46879`, which is what a bench setup answers to.
    public static let length = 5
    /// `PIN_FREE_ATTEMPTS`, `PIN_LOCKOUT_BASE_S`, `PIN_LOCKOUT_MAX_S`.
    public static let freeAttempts = 3

    private var authenticatedUntil: ContinuousClock.Instant?
    private var lockedOutUntil: ContinuousClock.Instant?
    public private(set) var failures = 0

    public init() {}

    public func isAuthenticated(at now: ContinuousClock.Instant = .now) -> Bool {
        guard let authenticatedUntil else { return false }
        return now < authenticatedUntil
    }

    /// Seconds left on the throttle, or nil when it is not running. The robot reports
    /// this itself; this is the local mirror so a countdown can tick between replies.
    public func lockoutRemaining(at now: ContinuousClock.Instant = .now) -> Duration? {
        guard let lockedOutUntil, now < lockedOutUntil else { return nil }
        return now.duration(to: lockedOutUntil)
    }

    public var attemptsBeforeLockout: Int {
        max(0, Self.freeAttempts - failures)
    }

    public mutating func authenticated(at now: ContinuousClock.Instant = .now) {
        authenticatedUntil = now.advanced(by: Self.ttl)
        lockedOutUntil = nil
        failures = 0
    }

    public mutating func failed(at now: ContinuousClock.Instant = .now) {
        failures += 1
        authenticatedUntil = nil
    }

    /// Applied from the robot's own `Try again in <n>s` reply, which is authoritative —
    /// the counter is robot-global and may already have been advanced by another phone.
    public mutating func lockedOut(for seconds: Int, at now: ContinuousClock.Instant = .now) {
        failures = max(failures, Self.freeAttempts + 1)
        authenticatedUntil = nil
        lockedOutUntil = now.advanced(by: .seconds(seconds))
    }

    /// Drops the session and **keeps the lockout**. This asymmetry is the whole point
    /// of the type: offering an immediate retry after a reconnect would walk the user
    /// straight into a refusal the robot never even evaluates.
    ///
    /// Two things trigger it, and the robot treats them identically: the link dropping,
    /// and any `CMD_*` script — its handler clears the robot's own flag in a `finally`,
    /// so the next privileged command needs the PIN again whether the script worked or not.
    public mutating func invalidate() {
        authenticatedUntil = nil
    }
}
