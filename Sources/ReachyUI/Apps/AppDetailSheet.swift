import ReachyKit
import SwiftUI

/// One app, and everything that can be done to it.
///
/// The job runs here rather than behind the sheet: an install takes a minute of
/// `uv pip install` output, and a user who dismissed the sheet would have nothing
/// to come back to.
struct AppDetailSheet: View {
    let app: RobotApp
    let model: AppStoreModel
    let session: RobotSession
    let install: AppInstallModel
    let dismiss: () -> Void

    @State private var confirmingRemoval = false
    @Environment(\.reachyPreviewMode) private var previewMode

    var body: some View {
        Form {
            Section {
                header
            }

            if let job = jobForThisApp {
                Section("Progress") {
                    JobProgressRow(state: job)
                    if install.isBusy || !install.log.entries.isEmpty {
                        LogConsoleView(
                            model: install.log,
                            source: app.title,
                            // The socket only wakes on a new line, so silence here
                            // is normal rather than a stall — `AppJobMonitor` is
                            // polling regardless.
                            emptyDescription: "Waiting for the robot to report progress…"
                        )
                        .frame(minHeight: 160)
                    }
                }
            } else {
                actions
            }

            if let summary = app.summary {
                Section("About") {
                    Text(summary)
                        .font(.subheadline)
                }
            }

            if let spaceID = app.spaceID, let url = URL(string: "https://huggingface.co/spaces/\(spaceID)") {
                Section {
                    Link(destination: url) {
                        Label("View on Hugging Face", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(app.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        install.dismiss()
                        dismiss()
                    }
                    .disabled(install.isBusy)
                }
            }
            .interactiveDismissDisabled(install.isBusy)
            .confirmationDialog(
                "Remove \(app.title)?",
                isPresented: $confirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    perform(.remove(installedApp ?? app))
                }
            } message: {
                Text("The app and its Python environment are deleted from the robot.")
            }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppArtworkTile(app: app, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.title)
                    .font(.title3.weight(.semibold))
                if let author = app.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if app.isOfficial {
                        Label("Official", systemImage: "checkmark.seal.fill")
                    }
                    if app.isPrivate {
                        Label("Private", systemImage: "lock.fill")
                    }
                    if let likes = app.likes, likes > 0 {
                        Label("\(likes)", systemImage: "heart.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var actions: some View {
        Section {
            if let installed = installedApp {
                if model.isRunning(app) {
                    Button("Stop", systemImage: "stop.fill", role: .destructive) {
                        Task { await model.stop(session: session) }
                    }
                } else {
                    Button("Start", systemImage: "play.fill") {
                        Task { await model.start(app, session: session) }
                    }
                    // Starting evicts whatever holds the robot; the daemon refuses
                    // with a 400 rather than taking it, and a remote session is not
                    // ours to take at all.
                    .disabled(model.busy || model.isHeldRemotely || model.runningApp != nil)
                }

                if model.hasUpdate(app) {
                    Button("Update", systemImage: "arrow.down.circle") {
                        perform(.update(installed))
                    }
                }

                Toggle("Start on wake-up", isOn: startupBinding)
                    .disabled(model.busy)

                Button("Remove", systemImage: "trash", role: .destructive) {
                    confirmingRemoval = true
                }
            } else {
                Button("Install", systemImage: "arrow.down.circle.fill") {
                    perform(.install(app))
                }
                .disabled(app.isPrivate && !canInstallPrivately)
            }
        } footer: {
            if app.isPrivate, !canInstallPrivately {
                Text("A private Space can only be installed once this robot is linked to your Hugging Face account.")
            } else if model.isHeldRemotely {
                Text("Someone is driving this robot over Hugging Face right now.")
            }
        }
    }

    private var installedApp: RobotApp? {
        model.installedTwin(of: app)
    }

    /// The daemon fetches a private Space with the token it stores, so this is
    /// about the *robot's* account, not about being signed in on this device.
    private var canInstallPrivately: Bool {
        session.canLinkHuggingFace
    }

    private var jobForThisApp: AppInstallModel.State? {
        guard let operation = install.operation else { return nil }
        let subject = operation.app
        guard subject.id == app.id || subject.name == installedApp?.name else { return nil }
        return install.state
    }

    private var startupBinding: Binding<Bool> {
        Binding(
            get: { model.isStartupApp(app) },
            set: { isOn in
                Task { await model.setStartupApp(isOn ? app : nil, session: session) }
            }
        )
    }

    private func perform(_ operation: AppInstallModel.Operation) {
        guard !previewMode else { return }
        Task {
            await install.perform(operation)
            await model.reloadInstalled(session: session)
        }
    }
}

/// What the job is doing, in one row.
struct JobProgressRow: View {
    let state: AppInstallModel.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .running(operation):
            Label {
                Text("\(operation.title) \(operation.app.title)…")
            } icon: {
                ProgressView()
                    .controlSize(.small)
            }
        case .succeeded:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(_, reason):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Failed")
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        case .daemonRestarted:
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("The robot restarted")
                    Text("It may have finished — check the installed list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            }
        }
    }
}
