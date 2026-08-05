import ReachyKit
import SwiftUI

/// What the running app is doing, in the one wording the dock and the expanded
/// sheet both use.
///
/// It lives in its own type rather than as a `private var` on the dock because two
/// surfaces render it: a user who reads "Stopping…" on the strip and "Running" in
/// the sheet has been told the robot is in two states at once.
///
/// The daemon's vocabulary is deliberately thin — five process states and nothing
/// about what the app is *doing*. A semantic state ("listening", "thinking") comes
/// from the app's own port, not from here, and slots in as a further case once that
/// channel exists.
struct RunningAppStatusChip: View {
    let status: RobotAppStatus
    /// The robot went quiet. The app may well still be running — we simply cannot
    /// say, and a confident "Running" would be a guess.
    var isReachable = true
    var font: Font = .caption

    var body: some View {
        Text(Self.description(of: status, isReachable: isReachable))
            .font(font)
            .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .lineLimit(2)
    }

    private var isError: Bool {
        status.state == .error
    }

    /// The state in one phrase, with no failure detail. What the sheet puts in a
    /// `LabeledContent`, where the traceback gets a row of its own.
    static func title(of status: RobotAppStatus, isReachable: Bool = true) -> String {
        guard isReachable else { return "Robot unreachable" }
        return switch status.state {
        case .starting: "Starting…"
        case .running: "Running"
        case .stopping: "Stopping…"
        case .done: "Finished"
        case .error: "Stopped with an error"
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
