import ReachyKit
import SwiftUI

/// Recorded moves from the Pollen HF libraries: pick a library, tap to play.
struct MovesScreen: View {
    let session: RobotSession

    @State private var model = MovesModel()

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Library", selection: $model.selection) {
                    ForEach(MovesModel.libraries.indices, id: \.self) { index in
                        Text(MovesModel.libraries[index].title).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                if model.loading {
                    ProgressView()
                } else if model.moves.isEmpty {
                    Text("No moves").foregroundStyle(.secondary)
                }
                ForEach(model.moves, id: \.self) { move in
                    Button {
                        Task { await model.play(move, session: session) }
                    } label: {
                        HStack {
                            Text(MovesModel.displayName(move))
                            Spacer()
                            if session.currentMove?.move == move {
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.iterative)
                            } else {
                                Image(systemName: "play.circle")
                            }
                        }
                    }
                    .disabled(model.startingMove || session.isStoppingMove)
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
                Task { await model.load(session: session, refresh: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.loading)
        }
        .task(id: model.selection) {
            await model.load(session: session)
        }
        .onDisappear {
            Task { await session.stopMove() }
        }
    }
}
