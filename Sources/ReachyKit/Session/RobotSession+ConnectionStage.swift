import Foundation

/// Projects the connection phase onto the stepper's rows.
///
/// Kept here rather than in the view so the mapping is testable as a plain
/// table, and so progress is monotonic by construction: the outcome is derived
/// from the phase every time instead of being accumulated, which is what forces
/// upstream to carry a high-water mark.
public extension RobotSession.ConnectionPhase {
    func outcome(for stage: RobotSession.ConnectionStage) -> RobotSession.StageOutcome {
        switch self {
        case .idle: .pending
        case .connected, .unreachable: .done
        case let .connecting(step): step.outcome(for: stage)
        }
    }
}

private extension RobotSession.ConnectionStep {
    func outcome(for stage: RobotSession.ConnectionStage) -> RobotSession.StageOutcome {
        switch (self, stage) {
        case (.handshaking, .connect): .active
        case (.handshaking, .backend): .pending
        case (.checkingBackend, .connect): .done
        case (.checkingBackend, .backend): .active
        case (.backendUnavailable, .connect): .done
        case (.backendUnavailable, .backend): .attention
        case let (.failed(failedStage, _), _):
            if stage == failedStage {
                .failed
            } else {
                stage.rawValue < failedStage.rawValue ? .done : .pending
            }
        }
    }
}
