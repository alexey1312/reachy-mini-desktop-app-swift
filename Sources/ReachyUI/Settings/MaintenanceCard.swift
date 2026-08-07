import ReachyDesign
import ReachyKit
import SwiftUI

/// Freeing the robot's disk, and the one way to uninstall every app at once.
///
/// Both routes live at the app root under `--wireless-version`, so this whole
/// section is absent on a Lite robot and over the relay — `canPerformMaintenance`
/// answers for both.
struct MaintenanceCard: View {
    let session: RobotSession

    @State private var model: MaintenanceModel

    /// `@MainActor` because `MaintenanceModel` is: a defaulted argument whose
    /// value is main-actor-isolated compiles in the SwiftPM targets and not in
    /// the `Apps/` ones, where it is evaluated nonisolated.
    @MainActor
    init(session: RobotSession, model: MaintenanceModel? = nil) {
        self.session = session
        _model = State(initialValue: model ?? MaintenanceModel())
    }

    var body: some View {
        Section {
            action(
                .clearHuggingFaceCache,
                description: .reachy("Model weights the robot has downloaded. An app fetches what it needs again."),
                button: .reachy("Clear Hugging Face cache"),
                systemImage: "arrow.down.circle.dotted"
            )
            action(
                .resetApps,
                description: resetDescription,
                button: .reachy("Uninstall all apps"),
                systemImage: "trash"
            )
            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(.reachy("Maintenance"))
        } footer: {
            Text(.reachy("Neither can be undone from here."))
        }
        .confirmationDialog(
            confirmation.title,
            isPresented: isConfirming,
            titleVisibility: .visible
        ) {
            if let pending = model.confirming {
                Button(confirmation.confirm, role: .destructive) {
                    Task { await model.perform(pending, session: session) }
                }
            }
        } message: {
            Text(confirmation.message)
        }
    }

    /// The robot's own dashboard puts the sentence above the button, and it is
    /// the right way round for something irreversible: the reader meets what it
    /// does before they meet the thing that does it.
    private func action(
        _ action: MaintenanceModel.Action,
        description: LocalizedStringResource,
        button: LocalizedStringResource,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(role: .destructive) {
                    model.confirming = action
                } label: {
                    Label(button, systemImage: systemImage)
                }
                .buttonStyle(.borderless)
                .disabled(model.isBusy || isBlocked(action))
                Spacer()
                trailing(for: action)
            }
        }
    }

    @ViewBuilder
    private func trailing(for action: MaintenanceModel.Action) -> some View {
        if model.running == action {
            ProgressView().controlSize(.small)
        } else if model.finished == action {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(.reachy("Done"))
        }
    }

    /// Names the app in the way, rather than leaving a greyed-out button with no
    /// explanation — the reader would have no idea what to do about it.
    private var resetDescription: LocalizedStringResource {
        if let blocking = model.blockingApp(session) {
            .reachy("Stop \(blocking.title) first — uninstalling deletes the environment it is running in.")
        } else {
            .reachy("Every installed app, and the Python environment they share.")
        }
    }

    private func isBlocked(_ action: MaintenanceModel.Action) -> Bool {
        action == .resetApps && model.blockingApp(session) != nil
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { model.confirming != nil },
            set: { presented in
                if !presented { model.confirming = nil }
            }
        )
    }

    /// A type rather than a tuple, and its three keys deliberately do not echo
    /// the button labels: the catalogue derives a Swift symbol per key, and two
    /// keys differing only in punctuation — `Uninstall all apps` against
    /// `Uninstall all apps?` — collide as a hard `xcstringstool` build error.
    private struct Confirmation {
        let title: LocalizedStringResource
        let message: LocalizedStringResource
        let confirm: LocalizedStringResource
    }

    private var confirmation: Confirmation {
        switch model.confirming {
        case .resetApps:
            Confirmation(
                title: .reachy("Remove every app?"),
                message: .reachy("Every app is deleted from the robot, along with the Python environment they share."),
                confirm: .reachy("Uninstall all")
            )
        // `.clearHuggingFaceCache` and nil share this arm: the dialog is only on
        // screen while `confirming` is set, and the property has to answer anyway.
        default:
            Confirmation(
                title: .reachy("Clear cached models?"),
                // swiftlint:disable:next line_length
                message: .reachy("Downloaded model weights are deleted. The robot downloads them again when an app needs them."),
                confirm: .reachy("Clear cache")
            )
        }
    }
}
