import ReachyKit
import SwiftUI

/// Recorded moves from the Pollen HF libraries: pick a library, tap to play.
struct MovesScreen: View {
    let address: RobotAddress

    /// Upstream `src/constants/choreographies.ts` libraries
    private static let libraries: [(title: String, dataset: String)] = [
        ("Dances", "pollen-robotics/reachy-mini-dances-library"),
        ("Emotions", "pollen-robotics/reachy-mini-emotions-library"),
        ("Music", "Anne-Charlotte/music"),
    ]

    @State private var selection = 0
    @State private var moves: [String] = []
    @State private var loading = false
    @State private var playingMove: String?
    @State private var playingUUID: String?
    @State private var lastError: String?
    @State private var connection: RobotConnection?

    var body: some View {
        Form {
            Section {
                Picker("Library", selection: $selection) {
                    ForEach(Self.libraries.indices, id: \.self) { i in
                        Text(Self.libraries[i].title).tag(i)
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
                            if playingMove == move {
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.iterative)
                            } else {
                                Image(systemName: "play.circle")
                            }
                        }
                    }
                }
            }
            if playingUUID != nil {
                Section {
                    Button("Stop", role: .destructive) { stop() }
                }
            }
            if let lastError {
                Section {
                    Text(lastError)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Moves")
        .onAppear { setup() }
        .onChange(of: selection) { load() }
        .onDisappear { stop() }
    }

    private func displayName(_ move: String) -> String {
        move.replacingOccurrences(of: "_", with: " ")
    }

    private func setup() {
        do {
            connection = try RobotConnection(address: address)
            load()
        } catch {
            lastError = "\(error)"
        }
    }

    private func load() {
        guard let connection else { return }
        let dataset = Self.libraries[selection].dataset
        loading = true
        moves = []
        lastError = nil
        Task {
            defer { loading = false }
            do {
                moves = try await connection.listMoves(dataset: dataset)
            } catch {
                lastError = "\(error)"
            }
        }
    }

    private func play(_ move: String) {
        guard let connection else { return }
        let dataset = Self.libraries[selection].dataset
        lastError = nil
        Task {
            do {
                if let playingUUID {
                    try? await connection.stopMove(uuid: playingUUID)
                }
                playingMove = move
                playingUUID = try await connection.playMove(dataset: dataset, move: move)
            } catch {
                playingMove = nil
                lastError = "\(error)"
            }
        }
    }

    private func stop() {
        guard let connection, let uuid = playingUUID else { return }
        playingMove = nil
        playingUUID = nil
        Task { try? await connection.stopMove(uuid: uuid) }
    }
}
