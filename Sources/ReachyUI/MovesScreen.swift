import ReachyKit
import SwiftUI

/// Recorded moves from the Pollen HF libraries: pick a library, tap to play.
struct MovesScreen: View {
    let session: RobotSession

    /// Upstream `src/constants/choreographies.ts` libraries
    private static let libraries: [(title: String, dataset: String)] = [
        ("Dances", "pollen-robotics/reachy-mini-dances-library"),
        ("Emotions", "pollen-robotics/reachy-mini-emotions-library"),
        ("Music", "Anne-Charlotte/music"),
    ]

    @State private var selection = 0
    @State private var moves: [String] = []
    @State private var loading = false
    @State private var startingMove = false

    var body: some View {
        Form {
            Section {
                Picker("Library", selection: $selection) {
                    ForEach(Self.libraries.indices, id: \.self) { index in
                        Text(Self.libraries[index].title).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                if loading {
                    ProgressView()
                } else if moves.isEmpty {
                    Text("No moves").foregroundStyle(.secondary)
                }
                ForEach(moves, id: \.self) { move in
                    Button {
                        play(move)
                    } label: {
                        HStack {
                            Text(displayName(move))
                            Spacer()
                            if session.currentMove?.move == move {
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.iterative)
                            } else {
                                Image(systemName: "play.circle")
                            }
                        }
                    }
                    .disabled(startingMove || session.isStoppingMove)
                }
            }
            if let lastError = session.lastError {
                Section {
                    Text(lastError)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Moves")
        .safeAreaInset(edge: .bottom) {
            if session.currentMove != nil {
                Button {
                    Task { await session.stopMove() }
                } label: {
                    HStack(spacing: 8) {
                        if session.isStoppingMove {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "stop.fill")
                        }
                        Text(session.isStoppingMove ? "Stopping…" : "Stop")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.red)
                .disabled(session.isStoppingMove)
                .padding()
            }
        }
        .toolbar {
            Button {
                Task { await load(refresh: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(loading)
        }
        .task(id: selection) {
            await load()
        }
        .onDisappear {
            Task { await session.stopMove() }
        }
    }

    private func displayName(_ move: String) -> String {
        move.replacingOccurrences(of: "_", with: " ")
    }

    @MainActor
    private func load(refresh: Bool = false) async {
        let dataset = Self.libraries[selection].dataset
        loading = true
        defer { loading = false }
        do {
            let loaded = try await session.moves(in: dataset, refresh: refresh)
            guard !Task.isCancelled else { return }
            moves = loaded
        } catch {
            if !Task.isCancelled {
                moves = []
            }
        }
    }

    private func play(_ move: String) {
        let dataset = Self.libraries[selection].dataset
        startingMove = true
        Task {
            defer { startingMove = false }
            try? await session.playMove(dataset: dataset, move: move)
        }
    }
}
