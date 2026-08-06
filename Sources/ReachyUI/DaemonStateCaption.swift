import Foundation
import ReachyDesign
import ReachyKit

/// The daemon's process state in words a reader can act on.
///
/// Three screens used to show `String(describing:)` of the generated enum, which
/// put `notInitialized` in front of the user: a camel-cased dump of a wire value,
/// untranslatable by construction and already ugly in English.
///
/// The mapping lives here rather than in `ReachyKit` for the reason the whole
/// package graph is arranged around — `ReachyDesign` is the bottom of the stack and
/// `ReachyKit` does not link it, so a caller maps its own domain type onto a
/// presentation value, never the other way.
enum DaemonStateCaption {
    static func text(for state: Components.Schemas.DaemonState) -> LocalizedStringResource {
        switch state {
        case .notInitialized: .reachy("Not started")
        case .starting: .reachy("Starting up")
        case .running: .reachy("Running")
        case .stopping: .reachy("Shutting down")
        case .stopped: .reachy("Stopped")
        case .error: .reachy("Failed")
        }
    }
}
