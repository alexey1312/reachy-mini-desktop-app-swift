import ReachyKit
import ReachyScene
import SwiftUI

/// Live 3D model of the robot. Read-only: it mirrors the state stream and never
/// sends a command.
struct RobotViewerScreen: View {
    let address: RobotAddress

    @State private var model: RobotSceneModel?
    @State private var setupError: String?

    var body: some View {
        content
            .navigationTitle("3D model")
            .onAppear { start() }
            .onDisappear {
                model?.stop()
                model = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            RobotSceneView(model: model)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .center) { status(for: model.phase) }
                .toolbar { toolbar(for: model) }
        } else {
            ContentUnavailableView(
                "3D model unavailable",
                systemImage: "cube.transparent",
                description: Text(setupError ?? "Connect to a robot to see its model.")
            )
        }
    }

    @ViewBuilder
    private func status(for phase: RobotSceneModel.Phase) -> some View {
        switch phase {
        case .idle, .fetchingDescription:
            loading("Reading the robot's description…", progress: nil)
        case let .downloadingMeshes(completed, total):
            // The first visit pulls every mesh over the robot's own Wi-Fi, which
            // is slow enough that a bare spinner reads as a hang.
            loading(
                "Downloading model \(completed)/\(total)…",
                progress: total > 0 ? Double(completed) / Double(total) : nil
            )
        case .buildingScene:
            loading("Building the scene…", progress: nil)
        case .ready:
            EmptyView()
        case let .failed(message):
            ContentUnavailableView(
                "Could not load the model",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }

    private func loading(_ title: String, progress: Double?) -> some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .frame(maxWidth: 220)
            } else {
                ProgressView()
            }
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ToolbarContentBuilder
    private func toolbar(for model: RobotSceneModel) -> some ToolbarContent {
        ToolbarItem {
            Menu {
                Button {
                    model.camera.reset()
                } label: {
                    Label("Reset view", systemImage: "arrow.counterclockwise")
                }
                Divider()
                Toggle("Place head from pose", isOn: Binding(
                    get: { model.placesHeadDirectly },
                    set: { model.placesHeadDirectly = $0 }
                ))
                Toggle("Solve Stewart linkage", isOn: Binding(
                    get: { model.solvesPassiveJoints },
                    set: { model.solvesPassiveJoints = $0 }
                ))
                if let lastFrameAt = model.lastFrameAt {
                    Text("Last frame \(lastFrameAt.formatted(date: .omitted, time: .standard))")
                }
                Text("Decoded frames: \(model.streamDiagnostics.decodedFrames)")
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
    }

    private func start() {
        guard model == nil else { return }
        do {
            let connection = try RobotConnection(address: address)
            let model = RobotSceneModel(address: address, client: connection)
            self.model = model
            model.start()
        } catch {
            setupError = "\(error)"
        }
    }
}
