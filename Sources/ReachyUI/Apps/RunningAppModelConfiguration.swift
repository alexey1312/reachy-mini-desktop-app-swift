import Foundation

/// Every duration `RunningAppModel` runs on, and what fixes each one.
///
/// In a file of its own because `RunningAppModel` reached SwiftLint's length limit,
/// and this is the half that is values rather than behaviour: three poll cadences,
/// two deadlines and one window, none of which reads anything.
///
/// Injected as a whole so a test can assert the choice without sleeping it — a fixed
/// `Task.sleep` before an assertion is a CI flake waiting to happen (project rule 7).
extension RunningAppModel {
    struct Configuration: Sendable, Equatable {
        /// A transition the user is watching finish.
        var transitioning: Duration = .milliseconds(1500)
        /// Steady state: identity only changes when somebody acts, and every one of
        /// those actions already writes through `recordRunning`.
        var running: Duration = .seconds(10)
        /// Nothing to watch. Still worth asking, because an app can be started from
        /// the widget, the robot's own dashboard, or a wake-up autostart.
        var idle: Duration = .seconds(15)
        /// How long `stopping` may last before it is called stuck.
        ///
        /// The daemon gives the app 20 s to honour SIGINT and then kills it
        /// (`apps/manager.py:301`), so a normal stop is over in seconds and a long
        /// one is over in twenty. 40 s clears both without overlapping either.
        var stoppingDeadline: Duration = .seconds(40)
        /// The same for `starting`, at the value upstream uses for an app launch
        /// (`.claude/rules/daemon-api.md`). Longer because a cold start pays for an
        /// interpreter, a model load and whatever the app fetches.
        var startingDeadline: Duration = .seconds(120)
        /// How long a refused Stop or Restart stays in the strip's one caption line.
        ///
        /// It has to be shown there at all: the strip has nowhere else to put it, and
        /// a refusal shown nowhere reads as the command having worked. It has to stop
        /// being shown too — `lastError` is cleared only by a later *successful*
        /// command, so a refused Restart on an app that goes on running would keep the
        /// state phrase, and the conversation turn with it, off the strip for the rest
        /// of the session. Long enough to read two lines, short enough that the
        /// caption goes back to reporting the robot rather than a past tap.
        var actionFailureWindow: Duration = .seconds(30)
    }
}
