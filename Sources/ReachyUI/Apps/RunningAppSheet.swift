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

    /// The app's own settings page, when there is one to offer.
    ///
    /// `session.appSettingsURL(for:)` already answers nil without a declared port
    /// and without a LAN address; the two conditions added here are this screen's
    /// own. **Only while it is running**, because the process serving that page is
    /// the process that would have died — a crashed app takes its settings down
    /// with it, which is at its worst exactly when a bad setting is what crashed
    /// it. And only while the robot answers, so the row does not lead to a spinner
    /// that can never resolve.
    private var settingsURL: URL? {
        guard status.state == .running, isReachable else { return nil }
        return session.appSettingsURL(for: status.app)
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
                    //
                    // `.shownSeparately` because `failureRow` is right below with
                    // the whole tail in it — inlining the crash here printed the
                    // same text twice, once cut off after two lines.
                    RunningAppCaption.label(
                        of: status,
                        failure: .shownSeparately,
                        conversationTurn: model.conversationTurn,
                        isReachable: isReachable,
                        font: .body
                    )
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

            if let settingsURL {
                Section {
                    NavigationLink {
                        AppSettingsScreen(url: settingsURL)
                    } label: {
                        Label(.reachy("Settings"), systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text(.reachy("The app's own page, served by the robot on this network."))
                }
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
