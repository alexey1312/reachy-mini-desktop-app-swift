import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

private final class MovesUIClient: RobotAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var listCalls = 0
    private(set) var played: [(String, String)] = []
    private let movesByDataset: [String: [String]]
    private var failingDatasets: Set<String> = []

    init(movesByDataset: [String: [String]] = [:]) {
        self.movesByDataset = movesByDataset
    }

    struct ListFailure: Error {}

    func setDataset(_ dataset: String, failing: Bool) {
        lock.withLock {
            if failing {
                failingDatasets.insert(dataset)
            } else {
                failingDatasets.remove(dataset)
            }
        }
    }

    private var status: Components.Schemas.DaemonStatus {
        let json = """
        {"robot_name":"ui-test","state":"running","wireless_version":false,
         "desktop_app_daemon":false,"simulation_enabled":true,"mockup_sim_enabled":false,
         "backend_status":{"motor_control_mode":"enabled","error":null}}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Components.Schemas.DaemonStatus.self, from: Data(json.utf8))
    }

    func handshake() async throws -> RobotConnection.Handshake {
        .init(identity: .init(name: "ui-test", daemonVersion: "1.9.0"), status: status)
    }

    func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        status
    }

    func wakeUp() async throws -> String {
        "wake"
    }

    func gotoSleep() async throws -> String {
        "sleep"
    }

    func listMoves(dataset: String) async throws -> [String] {
        try lock.withLock {
            listCalls += 1
            if failingDatasets.contains(dataset) {
                throw ListFailure()
            }
            return movesByDataset[dataset] ?? ["happy_move"]
        }
    }

    func playMove(dataset: String, move: String) async throws -> String {
        lock.withLock { played.append((dataset, move)) }
        return "ui-move"
    }

    func runningMoveUUIDs() async throws -> Set<String> {
        ["ui-move"]
    }
}

@MainActor
@Suite("MovesModel")
struct MovesModelTests {
    @Test("load renders moves and refresh bypasses the session cache")
    func loadAndRefresh() async {
        let client = MovesUIClient()
        let session = RobotSession { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        let model = MovesModel()

        await model.load(session: session)
        #expect(model.moves == ["happy_move"])
        #expect(!model.loading)
        await model.load(session: session)
        #expect(client.listCalls == 1)
        await model.load(session: session, refresh: true)
        #expect(client.listCalls == 2)
        session.disconnect()
    }

    /// The frame SwiftUI draws between the tab tap and `.task(id:)` running: `selection`
    /// has already moved, the load has not started yet, and whatever `moves` holds is on
    /// screen. Holding the previous library's list there is what reads as the jump.
    @Test("switching library never leaves the previous library's moves on screen")
    func switchingLibraryDropsStaleMoves() async {
        let client = MovesUIClient(movesByDataset: [
            MovesModel.libraries[0].dataset: ["dance_one"],
            MovesModel.libraries[1].dataset: ["joy"],
        ])
        let session = RobotSession { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        let model = MovesModel()

        await model.load(session: session)
        #expect(model.moves == ["dance_one"])

        model.selection = 1
        #expect(model.moves.isEmpty)

        await model.load(session: session)
        #expect(model.moves == ["joy"])
        session.disconnect()
    }

    /// Returning to a library already fetched this session must not re-enter the loading
    /// state: the list is known, so the rows belong on the very first frame.
    @Test("returning to a loaded library renders its moves without a load")
    func returningToLoadedLibraryIsInstant() async {
        let client = MovesUIClient(movesByDataset: [
            MovesModel.libraries[0].dataset: ["dance_one"],
            MovesModel.libraries[1].dataset: ["joy"],
        ])
        let session = RobotSession { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        let model = MovesModel()

        await model.load(session: session)
        model.selection = 1
        await model.load(session: session)

        model.selection = 0
        #expect(model.moves == ["dance_one"])
        #expect(!model.loading)
        session.disconnect()
    }

    /// A failed fetch must not look like an answer: caching it would short-circuit every
    /// later `load` and leave "No moves" on screen until someone found the Refresh button.
    @Test("a failed load is retried on the next visit to the tab")
    func failedLoadRetriesOnRevisit() async {
        let client = MovesUIClient(movesByDataset: [MovesModel.libraries[0].dataset: ["dance_one"]])
        client.setDataset(MovesModel.libraries[0].dataset, failing: true)
        let session = RobotSession { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        let model = MovesModel()

        await model.load(session: session)
        #expect(model.moves.isEmpty)
        #expect(!model.loading)
        #expect(client.listCalls == 1)

        client.setDataset(MovesModel.libraries[0].dataset, failing: false)
        await model.load(session: session)
        #expect(model.moves == ["dance_one"])
        #expect(client.listCalls == 2)
        session.disconnect()
    }

    /// The opposite half of the same policy: one bad round trip must not take away rows the
    /// robot already answered with.
    @Test("a failed refresh leaves the moves already on screen alone")
    func failedRefreshKeepsMoves() async {
        let client = MovesUIClient(movesByDataset: [MovesModel.libraries[0].dataset: ["dance_one"]])
        let session = RobotSession { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        let model = MovesModel()

        await model.load(session: session)
        #expect(model.moves == ["dance_one"])

        client.setDataset(MovesModel.libraries[0].dataset, failing: true)
        await model.load(session: session, refresh: true)

        #expect(model.moves == ["dance_one"])
        #expect(!model.loading)
        session.disconnect()
    }

    /// A library the daemon answers as genuinely empty is a real answer, so it is cached and
    /// not re-fetched — the distinction a failure-caching policy would erase.
    @Test("an empty library is cached rather than re-fetched")
    func emptyLibraryIsCached() async {
        let client = MovesUIClient(movesByDataset: [MovesModel.libraries[0].dataset: []])
        let session = RobotSession { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        let model = MovesModel()

        await model.load(session: session)
        #expect(model.moves.isEmpty)
        await model.load(session: session)

        #expect(client.listCalls == 1)
        session.disconnect()
    }

    @Test("play forwards the selected library and restores button state")
    func play() async {
        let client = MovesUIClient()
        let session = RobotSession { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        let model = MovesModel()
        model.selection = 1

        await model.play("joy", session: session)

        #expect(!model.startingMove)
        #expect(client.played.first?.0 == "pollen-robotics/reachy-mini-emotions-library")
        #expect(client.played.first?.1 == "joy")
        session.disconnect()
    }
}
