import ReachyKit

extension String? {
    /// Records why a daemon call refused, in the slot the screen that made it
    /// reads. Every model that shows a daemon failure goes through this.
    ///
    /// Not `Self.describe(error)`, which is what each of these models used to
    /// carry a copy of: `URLSession` reports an abandoned request as the single
    /// word "cancelled", so a model describing its own errors puts that word on
    /// its own tab the moment the session stops absorbing it. The filter lives in
    /// `RobotSession.message(for:)`, once, and logs on the way past.
    ///
    /// A cancelled call leaves the slot exactly as it was — it learned nothing,
    /// so it may neither report a failure nor clear one still being read.
    mutating func recordDaemonFailure(_ error: any Error) {
        self = RobotSession.message(for: error) ?? self
    }
}
