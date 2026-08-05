import Foundation
import Observation
import ReachyKit

@MainActor
@Observable
final class MovesModel {
    struct Library: Equatable {
        let title: String
        let dataset: String
    }

    static let libraries = [
        Library(title: "Dances", dataset: "pollen-robotics/reachy-mini-dances-library"),
        Library(title: "Emotions", dataset: "pollen-robotics/reachy-mini-emotions-library"),
        Library(title: "Music", dataset: "Anne-Charlotte/music"),
    ]

    var selection = 0
    private(set) var startingMove = false
    /// Keyed by dataset rather than held as one array: `selection` changes a frame before
    /// `.task(id:)` gets to run, so a shared array leaves the previous library's rows under
    /// the newly selected tab for as long as the fetch takes.
    private var movesByDataset: [String: [String]] = [:]
    private var loadingDataset: String?
    private var loadID: UUID?

    var selectedLibrary: Library {
        Self.libraries[selection]
    }

    /// Derived from `selection`, so the rows can never belong to another library.
    var moves: [String] {
        movesByDataset[selectedLibrary.dataset] ?? []
    }

    var loading: Bool {
        loadingDataset == selectedLibrary.dataset
    }

    func load(session: RobotSession, refresh: Bool = false) async {
        let dataset = selectedLibrary.dataset
        // A library fetched earlier this session is already on screen; entering the loading
        // state for it would only replace those rows with a spinner and put them back.
        if !refresh, movesByDataset[dataset] != nil {
            return
        }
        let requestID = UUID()
        loadID = requestID
        loadingDataset = dataset
        defer {
            if loadID == requestID {
                loadingDataset = nil
            }
        }
        do {
            let loaded = try await session.moves(in: dataset, refresh: refresh)
            guard !Task.isCancelled, loadID == requestID else { return }
            movesByDataset[dataset] = loaded
        } catch {
            // Deliberately records nothing. An absent key means "never fetched", so the next
            // visit to the tab retries, and a failed refresh leaves the rows already on screen
            // in place rather than clearing them over one bad round trip. A stored `[]` is
            // then a library the daemon really answered as empty, which is not worth retrying.
            // `session.lastError` carries the reason to the screen either way.
        }
    }

    func play(_ move: String, session: RobotSession) async {
        startingMove = true
        defer { startingMove = false }
        try? await session.playMove(dataset: selectedLibrary.dataset, move: move)
    }

    static func displayName(_ move: String) -> String {
        move.replacingOccurrences(of: "_", with: " ")
    }
}

#if DEBUG
    extension MovesModel {
        /// Lives here rather than in `Previews/`: `moves` and `loading` are `private(set)`, which
        /// `@testable` does not reach from another module.
        static func preview(
            moves: [String] = MovesModel.previewMoves,
            selection: Int = 0,
            loading: Bool = false,
            startingMove: Bool = false
        ) -> MovesModel {
            let model = MovesModel()
            model.selection = selection
            model.movesByDataset[model.selectedLibrary.dataset] = moves
            model.loadingDataset = loading ? model.selectedLibrary.dataset : nil
            model.startingMove = startingMove
            return model
        }

        static let previewMoves = [
            "happy_dance", "head_shake", "look_around", "nod_yes", "sad_slump", "wave_hello",
        ]
    }
#endif
