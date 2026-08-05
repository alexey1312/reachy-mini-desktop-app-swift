import ReachyKit
import SwiftUI

/// The robot's app store: what is installed, what the Hub offers, and what is
/// running right now.
struct AppStoreScreen: View {
    let session: RobotSession

    @State private var model: AppStoreModel
    @State private var install: AppInstallModel
    @State private var selected: RobotApp?
    @Environment(\.reachyPreviewMode) private var previewMode

    init(session: RobotSession, model: AppStoreModel = AppStoreModel(), install: AppInstallModel? = nil) {
        self.session = session
        _model = State(initialValue: model)
        _install = State(initialValue: install ?? AppInstallModel(session: session))
    }

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Picker("Section", selection: $model.section) {
                    ForEach(AppStoreModel.Section.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if model.isHeldRemotely {
                Section {
                    remoteSessionNotice
                }
            }

            if let lastError = model.lastError {
                Section {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if model.loading, model.visibleApps.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(model.visibleApps) { app in
                        Button {
                            selected = app
                        } label: {
                            AppStoreRow(
                                app: app,
                                isInstalled: model.isInstalled(app),
                                isRunning: model.isRunning(app),
                                hasUpdate: model.hasUpdate(app),
                                isStartupApp: model.isStartupApp(app)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if model.visibleApps.isEmpty, !model.loading {
                emptyState
            }
        }
        .navigationTitle("Apps")
        .searchable(text: $model.searchText, prompt: "Search apps")
        .minimizedSearchToolbar()
        .safeAreaInset(edge: .bottom) {
            if let running = model.runningApp {
                RunningAppBanner(status: running, busy: model.busy) { action in
                    Task {
                        switch action {
                        case .stop: await model.stop(session: session)
                        case .restart: await model.restart(session: session)
                        }
                    }
                }
                .padding()
            }
        }
        .toolbar {
            Button {
                Task { await model.load(session: session, refresh: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.loading)
        }
        .sheet(item: $selected) { app in
            NavigationStack {
                AppDetailSheet(app: app, model: model, session: session, install: install) { selected = nil }
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            guard !previewMode else { return }
            await model.load(session: session)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else if model.lastError != nil {
            ContentUnavailableView(
                "Store unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text("The robot could not reach Hugging Face. Pull to refresh once it is back online.")
            )
        } else {
            switch model.section {
            case .installed:
                ContentUnavailableView(
                    "No apps installed",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Browse Discover to install one from Hugging Face.")
                )
            case .discover:
                ContentUnavailableView(
                    "Nothing to show",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("The robot found no apps on Hugging Face.")
                )
            }
        }
    }

    /// A relay session holds the same lock a local app does, and the user cannot
    /// take it back from here — saying so beats a disabled button with no reason.
    private var remoteSessionNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("In use remotely")
                    .font(.subheadline.weight(.semibold))
                Text(
                    model.lockHolder.map { "\($0) is driving this robot over Hugging Face." }
                        ?? "Someone is driving this robot over Hugging Face."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.tint)
        }
    }
}

/// What is running, and the two things worth doing about it.
struct RunningAppBanner: View {
    enum Action {
        case stop
        case restart
    }

    let status: RobotAppStatus
    var busy = false
    let perform: (Action) -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppArtworkTile(app: status.app, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(status.app.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(stateDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                perform(.restart)
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(busy)

            Button {
                perform(.stop)
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(.red)
            .disabled(busy)
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var stateDescription: String {
        switch status.state {
        case .starting: "Starting…"
        case .running: "Running"
        case .stopping: "Stopping…"
        case .done: "Finished"
        case .error: status.error ?? "Stopped with an error"
        case let .unknown(state): state
        }
    }
}

private extension View {
    /// iOS 26 collapses a bottom search field into a button until it is used. The
    /// deployment floor is iOS 18, so this is opt-in per availability rather than
    /// a project-wide setting.
    ///
    /// The member is `.minimize`, not `.minimized` — Apple's own documentation for
    /// `searchToolbarBehavior(_:)` shows the latter in its example, and it does not
    /// compile.
    @ViewBuilder
    func minimizedSearchToolbar() -> some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                searchToolbarBehavior(.minimize)
            } else {
                self
            }
        #else
            self
        #endif
    }
}
