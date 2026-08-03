import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

private final class MovesUIClient: RobotAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var listCalls = 0
    private(set) var played: [(String, String)] = []

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

    func wakeUp() async throws {}
    func gotoSleep() async throws {}
    func listMoves(dataset _: String) async throws -> [String] {
        lock.withLock { listCalls += 1 }
        return ["happy_move"]
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
