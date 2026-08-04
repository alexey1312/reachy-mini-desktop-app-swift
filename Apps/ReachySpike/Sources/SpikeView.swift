import ReachyKit
import SwiftUI

/// Phase 0.4 device-check screen: discovery, manual connect, stream counter.
/// Checklist it serves — see docs/research/phase0.md.
struct SpikeView: View {
    @State private var model: SpikeModel
    @State private var discovery: RobotBrowser
    /// ReachyUI's `\.reachyPreviewMode` is internal to that module, so this screen carries its own
    /// switch: a preview hands in a seeded browser and must not also start Bonjour.
    private let browsesLiveNetwork: Bool

    /// `nil` defaults rather than `SpikeModel()`: a default argument is evaluated in a nonisolated
    /// context and both of these are main-actor isolated.
    @MainActor
    init(model: SpikeModel? = nil, discovery: RobotBrowser? = nil, browsesLiveNetwork: Bool = true) {
        _model = State(initialValue: model ?? SpikeModel())
        _discovery = State(initialValue: discovery ?? RobotBrowser())
        self.browsesLiveNetwork = browsesLiveNetwork
    }

    var body: some View {
        Form {
            discoverySection
            connectSection
            streamSection
        }
        .formStyle(.grouped)
        .onAppear {
            guard browsesLiveNetwork else { return }
            discovery.start()
        }
        .onDisappear { discovery.stop() }
    }

    private var discoverySection: some View {
        Section("Discovery (Bonjour)") {
            ForEach(Array(discovery.browserStates.sorted(by: { $0.key < $1.key })), id: \.key) { type, state in
                LabeledContent(type) {
                    Text(state).font(.caption.monospaced())
                }
            }
            if discovery.permissionLooksDenied {
                Label("Local Network permission denied", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                #if os(iOS)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                #endif
            }
            if discovery.services.isEmpty {
                Text("No robots found").foregroundStyle(.secondary)
            }
            ForEach(discovery.services) { service in
                LabeledContent(service.name) {
                    Text(service.type).font(.caption.monospaced())
                }
            }
            Button("Restart discovery") { discovery.start() }
        }
    }

    private var connectSection: some View {
        Section("Connection") {
            TextField("Host (IP or name.local)", text: $model.host)
                .autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            #endif
            Button("Connect (handshake)") {
                Task { await model.connect() }
            }
            if let summary = model.handshakeSummary {
                Text(summary).font(.caption.monospaced())
            }
            if let error = model.lastError {
                Text(error)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
            }
        }
    }

    private var streamSection: some View {
        Section("State stream (10 Hz by default)") {
            Button(model.isStreaming ? "Stop stream" : "Start stream") {
                model.toggleStream()
            }
            LabeledContent("Frames") { Text("\(model.frameCount)") }
            LabeledContent("Rate") { Text(String(format: "%.1f Hz", model.hertz)) }
            if model.streamDiagnostics.decodeFailures > 0 || model.streamDiagnostics.unsupportedFrames > 0 {
                Label(
                    "Invalid frames: \(model.invalidFrameCount)",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                if let failure = model.streamDiagnostics.lastFailureDescription {
                    Text(failure).font(.caption.monospaced())
                }
            }
        }
    }
}
