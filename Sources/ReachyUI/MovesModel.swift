import Foundation
import Observation
import ReachyDesign
import ReachyKit

@MainActor
@Observable
final class MovesModel {
    struct Library: Equatable {
        let title: LocalizedStringResource
        let dataset: String
        let loadingTitle: LocalizedStringResource
    }

    static let libraries = [
        Library(
            title: .reachy("Dances"),
            dataset: "pollen-robotics/reachy-mini-dances-library",
            loadingTitle: .reachy("Teaching the servos new steps…")
        ),
        Library(
            title: .reachy("Emotions"),
            dataset: "pollen-robotics/reachy-mini-emotions-library",
            loadingTitle: .reachy("Calibrating robot feelings…")
        ),
        Library(
            title: .reachy("Music"),
            dataset: "Anne-Charlotte/music",
            loadingTitle: .reachy("Warming up the tiny speakers…")
        ),
    ]

    var selection = 0 {
        didSet {
            guard Self.libraries.indices.contains(selection) else { return }
            let dataset = selectedLibrary.dataset
            if movesByDataset[dataset] == nil {
                // `.task(id:)` will retry this uncached library. Mark it pending now so
                // the frame drawn for the picker change cannot say "No moves" first.
                attemptedDatasets.remove(dataset)
            }
        }
    }

    private(set) var startingMove = false
    /// Keyed by dataset rather than held as one array: `selection` changes a frame before
    /// `.task(id:)` gets to run, so a shared array leaves the previous library's rows under
    /// the newly selected tab for as long as the fetch takes.
    private var movesByDataset: [String: [String]] = [:]
    private var loadingDataset: String?
    /// An absent result starts as loading, but after a failed request it must become
    /// an actionable error instead of an infinite spinner. A later visit still retries.
    private var attemptedDatasets: Set<String> = []
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

    /// Unlike `loading`, this only replaces an empty content area. A refresh of rows
    /// already on screen is deliberately non-blocking.
    var isContentLoading: Bool {
        movesByDataset[selectedLibrary.dataset] == nil
            && (loading || !attemptedDatasets.contains(selectedLibrary.dataset))
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
            attemptedDatasets.insert(dataset)
        } catch {
            guard !Task.isCancelled, loadID == requestID else { return }
            attemptedDatasets.insert(dataset)
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
            if loading {
                model.loadingDataset = model.selectedLibrary.dataset
                if !moves.isEmpty {
                    model.movesByDataset[model.selectedLibrary.dataset] = moves
                    model.attemptedDatasets.insert(model.selectedLibrary.dataset)
                }
            } else {
                model.movesByDataset[model.selectedLibrary.dataset] = moves
                model.attemptedDatasets.insert(model.selectedLibrary.dataset)
            }
            model.startingMove = startingMove
            return model
        }

        static let previewMoves = [
            "happy_dance", "head_shake", "look_around", "nod_yes", "sad_slump", "wave_hello",
        ]
    }
#endif
