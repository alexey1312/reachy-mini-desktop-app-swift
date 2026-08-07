import Foundation
@testable import ReachyKit
import Testing

private enum MoveProbe {
    case running(Set<String>)
    case failure
}

private enum MoveFailure: Error, CustomStringConvertible {
    case failed
    var description: String {
        "failed"
    }
}

private final class MoveRobotClient: RobotAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var nextUUID = 0
    private var running: [MoveProbe]
    private var activeUUID: String?
    var failStopMove = false
    var failStopSound = false
    private(set) var listCalls = 0
    private(set) var events: [String] = []
    private(set) var stopSoundCalls = 0

    init(running: [MoveProbe] = []) {
        self.running = running
    }

    private var status: Components.Schemas.DaemonStatus {
        let json = """
        {"robot_name":"testbot","state":"running","wireless_version":false,
         "desktop_app_daemon":false,"simulation_enabled":true,"mockup_sim_enabled":false,
         "backend_status":{"motor_control_mode":"enabled","error":null}}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Components.Schemas.DaemonStatus.self, from: Data(json.utf8))
    }

    func handshake() async throws -> RobotConnection.Handshake {
        .init(identity: .init(hardwareID: "hw", name: "testbot", daemonVersion: "1.9.0"), status: status)
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

    func listMoves(dataset _: String) async throws -> [String] {
        lock.withLock { listCalls += 1 }
        return ["happy_move", "wave"]
    }

    func playMove(dataset: String, move: String) async throws -> String {
        lock.withLock {
            nextUUID += 1
            activeUUID = "move-\(nextUUID)"
            events.append("play:\(dataset):\(move)")
            return activeUUID!
        }
    }

    func runningMoveUUIDs() async throws -> Set<String> {
        let probe = lock.withLock {
            running.isEmpty ? MoveProbe.running(activeUUID.map { [$0] } ?? []) : running.removeFirst()
        }
        switch probe {
        case let .running(uuids): return uuids
        case .failure: throw MoveFailure.failed
        }
    }

    func stopMove(uuid: String) async throws {
        let shouldFail = lock.withLock {
            events.append("stop:\(uuid)")
            activeUUID = nil
            return failStopMove
        }
        if shouldFail {
            throw MoveFailure.failed
        }
    }

    func stopSound() async throws {
        let shouldFail = lock.withLock {
            stopSoundCalls += 1
            events.append("sound")
            return failStopSound
        }
        if shouldFail {
            throw MoveFailure.failed
        }
    }
}

@MainActor
@Suite("RobotSession moves")
struct RobotSessionMoveTests {
    private func session(_ client: MoveRobotClient, movePoll: Duration = .seconds(5)) async -> RobotSession {
        var configuration = RobotSession.Configuration()
        configuration.pollInterval = .seconds(60)
        configuration.movePollInterval = movePoll
        let session = RobotSession(configuration: configuration) { _ in client }
        #expect(await session.connect(to: .init(host: "127.0.0.1")))
        return session
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("dataset results are cached until an explicit refresh")
    func cacheAndRefresh() async throws {
        let client = MoveRobotClient()
        let session = await session(client)
        #expect(try await session.moves(in: "library") == ["happy_move", "wave"])
        _ = try await session.moves(in: "library")
        #expect(client.listCalls == 1)
        _ = try await session.moves(in: "library", refresh: true)
        #expect(client.listCalls == 2)
        session.disconnect()
    }

    @Test("replacing playback stops the old move before starting the new one")
    func replacementOrdering() async throws {
        let client = MoveRobotClient()
        let session = await session(client)
        try await session.playMove(dataset: "library", move: "first")
        try await session.playMove(dataset: "library", move: "second")
        let events = client.events
        #expect(events.first == "play:library:first")
        #expect(try #require(events.firstIndex(of: "stop:move-1")) < events.firstIndex(of: "play:library:second")!)
        #expect(session.currentMove?.uuid == "move-2")
        session.disconnect()
    }

    @Test("stop reports deterministic partial failures and clears playback")
    func stopFailures() async throws {
        let client = MoveRobotClient()
        let session = await session(client)
        try await session.playMove(dataset: "library", move: "first")
        client.failStopMove = true
        client.failStopSound = true
        // Returned rather than reported: both tasks are seen through, so there is
        // no single failure to throw and nothing for the session to hold.
        let failures = await session.stopMove()
        #expect(session.currentMove == nil)
        #expect(failures == ["Move: failed", "Sound: failed"])
        #expect(session.robotError == nil)
        session.disconnect()
    }

    @Test("transient poll errors and a hit reset completion hysteresis")
    func naturalCompletionHysteresis() async throws {
        let client = MoveRobotClient(running: [
            .failure, .running([]), .running(["move-1"]), .running([]), .running([]),
        ])
        let session = await session(client, movePoll: .milliseconds(20))
        try await session.playMove(dataset: "library", move: "first")
        await waitUntil(session.currentMove == nil)
        #expect(session.currentMove == nil)
        #expect(client.stopSoundCalls == 1)
        session.disconnect()
    }
}
