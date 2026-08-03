import ReachyKit

extension RobotSession.PowerTransition {
    /// Starting a cold backend can take up to 90 s — silence would read as a hang.
    /// Shared by the connection stepper and the connected-robot screen, which can
    /// both be showing a backend start.
    var statusText: String {
        switch self {
        case .startingBackend: "Starting the robot backend… this can take a minute"
        case .wakingUp: "Waking up…"
        case .goingToSleep: "Going to sleep…"
        }
    }
}
