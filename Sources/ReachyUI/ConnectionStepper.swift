import ReachyKit
import SwiftUI

/// The connection attempt as ordered steps, so a failure names the step it
/// happened on — "the daemon never answered" and "the daemon answered but the
/// robot backend is down" need different things from the user.
///
/// Always a `Section`: the caller decides whether to drop it into the discovery
/// form (background candidate sweep) or give it a form of its own (needs a decision).
struct ConnectionStepper: View {
    let session: RobotSession

    var body: some View {
        Section {
            ForEach(RobotSession.ConnectionStage.allCases, id: \.self, content: row)
            if let message = daemonMessage {
                Label(message, systemImage: "wrench.and.screwdriver")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            actions
        } header: {
            Text(headerText)
        }
    }

    private func row(for stage: RobotSession.ConnectionStage) -> some View {
        let outcome = session.phase.outcome(for: stage)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            icon(for: outcome)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: stage))
                if let detail = detail(for: stage) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func icon(for outcome: RobotSession.StageOutcome) -> some View {
        switch outcome {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .active:
            ProgressView()
                .controlSize(.small)
                // SF Symbols carry a text baseline and sit on the title's line by
                // themselves; a spinner has none, so the row's `.firstTextBaseline`
                // alignment would drop it below the title. Sit it on the baseline.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .attention: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let transition = session.powerTransition {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(transition.statusText)
                    // The daemon state walks stopped → starting → running on its own
                    // as `waitForDaemonRunning` refreshes it: real progress, not a timer.
                    if let state = session.lastStatus?.state {
                        Text("Daemon state: \(String(describing: state))")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
        } else if isBackendUnavailable {
            Button("Start robot backend") {
                Task { await session.startBackend() }
            }
            Button("Continue anyway") {
                session.proceedWithoutBackend()
            }
            cancelButton
        } else if isFailed {
            if let address = session.address {
                Button("Try again") {
                    Task { await session.connect(to: address) }
                }
            }
            cancelButton
        }
    }

    /// `disconnect()` is the whole cancel story: it invalidates the attempt and
    /// pauses automatic reconnect, which is what stops the 10 s rescan from
    /// reopening this very card moments later.
    private var cancelButton: some View {
        Button("Cancel", role: .cancel) {
            session.disconnect()
        }
    }

    private func title(for stage: RobotSession.ConnectionStage) -> String {
        switch stage {
        case .connect: "Connect to daemon"
        case .backend: "Robot backend"
        }
    }

    private func detail(for stage: RobotSession.ConnectionStage) -> String? {
        guard case let .connecting(step) = session.phase else { return nil }
        switch step {
        case let .failed(failedStage, message):
            return failedStage == stage ? message : nil
        case .backendUnavailable:
            return stage == .backend ? "The robot backend is not running" : nil
        case .checkingBackend:
            guard stage == .backend, let state = session.lastStatus?.state else { return nil }
            return "Daemon state: \(String(describing: state))"
        case .handshaking:
            return nil
        }
    }

    private var daemonMessage: String? {
        guard case let .connecting(.backendUnavailable(_, message)) = session.phase else { return nil }
        return message
    }

    private var headerText: String {
        let target = session.address?.displayString ?? "robot"
        return isFailed ? "Couldn't connect to \(target)" : "Connecting to \(target)"
    }

    private var isBackendUnavailable: Bool {
        if case .connecting(.backendUnavailable) = session.phase {
            return true
        }
        return false
    }

    private var isFailed: Bool {
        if case .connecting(.failed) = session.phase {
            return true
        }
        return false
    }
}
