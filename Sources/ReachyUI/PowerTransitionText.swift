import ReachyDesign
import ReachyKit

extension RobotSession.PowerTransition {
    /// Starting a cold backend can take up to 90 s — silence would read as a hang.
    /// Shared by the connection stepper and the connected-robot screen, which can
    /// both be showing a backend start.
    var statusText: String {
        switch self {
        case .startingBackend: String(localized: .reachy("Starting the robot backend… this can take a minute"))
        case .wakingUp: String(localized: .reachy("Waking up…"))
        case .goingToSleep: String(localized: .reachy("Going to sleep…"))
        }
    }
}
