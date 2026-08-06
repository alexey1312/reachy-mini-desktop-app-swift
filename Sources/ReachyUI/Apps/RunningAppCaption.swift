import ReachyDesign
import ReachyKit
import SwiftUI

/// What the running app is doing, in the one wording the dock and the expanded
/// sheet both use.
///
/// It lives in its own type rather than as a `private var` on the dock because two
/// surfaces render it: a user who reads "Stopping…" on the strip and "Running" in
/// the sheet has been told the robot is in two states at once.
///
/// A caption rather than a view of its own: the dock passes it to `AppRowLabel`,
/// which takes a `ReachyStatusLabel` and would have no use for a wrapper around
/// one. The shape of the label belongs to `ReachyDesign`; what belongs here is the
/// mapping from the daemon's process states onto a tone and a phrase.
///
/// The daemon's vocabulary is deliberately thin — five process states and nothing
/// about what the app is *doing*. A semantic state ("listening", "thinking") comes
/// from the app's own port, not from here, and slots in as a further case once that
/// channel exists.
enum RunningAppCaption {
    /// The dock's caption line, and the value of the sheet's `LabeledContent`.
    ///
    /// Two lines, because that is what the strip allows and what a crash needs.
    ///
    /// `@MainActor` because it builds a `View`, and `View` carries that isolation;
    /// the mappings below are plain values and stay off it.
    @MainActor
    static func label(
        of status: RobotAppStatus,
        isReachable: Bool = true,
        font: Font = Typography.status
    ) -> ReachyStatusLabel {
        ReachyStatusLabel(
            text: description(of: status, isReachable: isReachable),
            tone: tone(of: status),
            font: font,
            lineLimit: 2
        )
    }

    /// Only a crash is coloured. "Running" stays quiet: the strip is on screen
    /// solely because something is running, so saying it again in green would tell
    /// the reader nothing they cannot already see.
    static func tone(of status: RobotAppStatus) -> StatusTone {
        status.state == .error ? .failed : .idle
    }

    /// The state in one phrase, with no failure detail. What the sheet puts in a
    /// `LabeledContent`, where the traceback gets a row of its own.
    ///
    /// A resolved `String` rather than a `LocalizedStringResource`, and that is
    /// forced rather than chosen: `.unknown(state)` carries the daemon's own word
    /// for a state this build has never heard of, and `description(of:)` below
    /// substitutes a traceback. A slot that has to hold a runtime string alongside
    /// a translated phrase resolves the phrase; it cannot stay a resource.
    static func title(of status: RobotAppStatus, isReachable: Bool = true) -> String {
        guard isReachable else { return String(localized: .reachy("Robot unreachable")) }
        return switch status.state {
        case .starting: String(localized: .reachy("Starting…"))
        case .running: String(localized: .reachy("Running"))
        case .stopping: String(localized: .reachy("Stopping…"))
        case .done: String(localized: .reachy("Finished"))
        case .error: String(localized: .reachy("Stopped with an error"))
        // Carried through rather than replaced with "Unknown": a later daemon's
        // own word for the state is more use than ours (project rule 3).
        case let .unknown(state): state
        }
    }

    /// The same, with the failure inlined. The dock has one caption line and no
    /// room for a second row, so a crash has to say what it was right there.
    static func description(of status: RobotAppStatus, isReachable: Bool = true) -> String {
        guard isReachable else { return title(of: status, isReachable: false) }
        if status.state == .error, let error = status.error {
            return error
        }
        return title(of: status)
    }
}
