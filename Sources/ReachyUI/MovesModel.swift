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
    private(set) var moves: [String] = []
    private(set) var loading = false
    private(set) var startingMove = false
    private var loadID: UUID?

    var selectedLibrary: Library {
        Self.libraries[selection]
    }

    func load(session: RobotSession, refresh: Bool = false) async {
        let requestID = UUID()
        let dataset = selectedLibrary.dataset
        loadID = requestID
        loading = true
        defer {
            if loadID == requestID {
                loading = false
            }
        }
        do {
            let loaded = try await session.moves(in: dataset, refresh: refresh)
            guard !Task.isCancelled, loadID == requestID, selectedLibrary.dataset == dataset else { return }
            moves = loaded
        } catch {
            guard !Task.isCancelled, loadID == requestID else { return }
            moves = []
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
