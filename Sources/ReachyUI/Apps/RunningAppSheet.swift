import ReachyDesign
import ReachyKit
import SwiftUI

/// The running app, expanded out of the dock.
///
/// Dismissing it minimises back to the strip — the app keeps running, and only the
/// explicit Stop button ends it. That is the contract a Telegram Mini App has, and
/// the reason the toolbar says "Minimise" rather than "Done".
///
/// Deliberately *not* an extension of `AppDetailSheet`: that one is about a
/// catalogue entry (install, update, remove, start-on-wake-up) and needs the store
/// and installer models, which the root view does not own. The two share the header
/// and nothing else.
struct RunningAppSheet: View {
    let session: RobotSession
    let model: RunningAppModel
    let status: RobotAppStatus

    private var isReachable: Bool {
        model.isReachable(session)
    }

    var body: some View {
        Form {
            Section {
                AppIdentityHeader(app: status.app)
            }

            Section(.reachy("Status")) {
                LabeledContent(.reachy("State")) {
                    // `.body` and not a `Typography` role: here the state is the
                    // *value* of a form row, so it takes the size the row's own
                    // label already has.
                    RunningAppCaption.label(of: status, isReachable: isReachable, font: .body)
                }
                if !isReachable {
                    Text(
                        .reachy(
                            // swiftlint:disable:next line_length
                            "The robot stopped answering. The app may still be running — these controls cannot reach it."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let error = status.error {
                    failureRow(error)
                }
                if let lastError = model.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                controls
            }

            if let summary = status.app.summary {
                Section(.reachy("About")) {
                    Text(summary)
                        .font(.subheadline)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(status.app.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.reachy("Minimize")) { model.isExpanded = false }
                }
            }
    }

    /// The last thing the app printed before it died. The daemon keeps ten stderr
    /// lines here, and on a robot whose journal is not served over the network this
    /// is the only crash output there is.
    private func failureRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.reachy("Last output"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(error)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if status.state == .error {
            Button(.reachy("Dismiss"), systemImage: "xmark") {
                model.dismissFailure(session)
            }
        } else {
            Button(.reachy("Restart"), systemImage: "arrow.clockwise") {
                Task { await model.restart(session: session) }
            }
            .disabled(model.busy || !isReachable)

            Button(.reachy("Stop"), systemImage: "stop.fill", role: .destructive) {
                Task { await model.stop(session: session) }
            }
            .disabled(model.busy || !isReachable)
        }
    }
}
