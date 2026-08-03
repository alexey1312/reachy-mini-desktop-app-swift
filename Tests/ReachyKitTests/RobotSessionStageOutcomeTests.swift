@testable import ReachyKit
import Testing

/// The stepper's row model. Pure and total, so it is checked as a table rather
/// than driven through a session.
@Suite("Connection stage outcomes")
struct RobotSessionStageOutcomeTests {
    private struct Expectation {
        let phase: RobotSession.ConnectionPhase
        let connect: RobotSession.StageOutcome
        let backend: RobotSession.StageOutcome
    }

    @Test("every phase maps to a monotonic pair of stage outcomes")
    func stageOutcomes() {
        let identity = RobotIdentity(hardwareID: "hw-1", name: "testbot", daemonVersion: "1.9.0")
        let expectations = [
            Expectation(phase: .idle, connect: .pending, backend: .pending),
            Expectation(phase: .connecting(.handshaking), connect: .active, backend: .pending),
            Expectation(
                phase: .connecting(.checkingBackend(identity)), connect: .done, backend: .active
            ),
            Expectation(
                phase: .connecting(.backendUnavailable(identity, daemonMessage: nil)),
                connect: .done, backend: .attention
            ),
            Expectation(
                phase: .connecting(.failed(.connect, message: "x")), connect: .failed, backend: .pending
            ),
            Expectation(
                phase: .connecting(.failed(.backend, message: "x")), connect: .done, backend: .failed
            ),
            Expectation(phase: .connected(identity), connect: .done, backend: .done),
            Expectation(phase: .unreachable(identity), connect: .done, backend: .done),
        ]

        for expectation in expectations {
            #expect(
                expectation.phase.outcome(for: .connect) == expectation.connect,
                "connect stage for \(expectation.phase)"
            )
            #expect(
                expectation.phase.outcome(for: .backend) == expectation.backend,
                "backend stage for \(expectation.phase)"
            )
        }
    }
}
