import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

/// Records what the card asked the robot to delete, and can refuse.
private final class MaintenanceRecorder: @unchecked Sendable {
    var calls: [String] = []
    var failure: (any Error)?
}

/// A client speaking both protocols a session needs here: the four members every
/// double must supply, and `/cache/*` — which is what `canPerformMaintenance`
/// looks for.
private struct MaintenanceCapableClient: RobotAPIClient, CacheMaintenanceClient {
    let recorder: MaintenanceRecorder
    private let base = PreviewRobotClient()

    func handshake() async throws -> RobotConnection.Handshake {
        try await base.handshake()
    }

    func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        try await base.daemonStatus()
    }

    func wakeUp() async throws -> String {
        try await base.wakeUp()
    }

    func gotoSleep() async throws -> String {
        try await base.gotoSleep()
    }

    func clearHuggingFaceCache() async throws {
        recorder.calls.append("clear-hf")
        if let failure = recorder.failure { throw failure }
    }

    func resetApps() async throws {
        recorder.calls.append("reset-apps")
        if let failure = recorder.failure { throw failure }
    }
}

@MainActor
@Suite("Robot maintenance", .timeLimit(.minutes(1)))
struct MaintenanceModelTests {
    private struct Refused: Error, LocalizedError {
        var errorDescription: String? { "The robot could not delete it." }
    }

    private func session(
        recorder: MaintenanceRecorder = MaintenanceRecorder(),
        runningApp: RobotAppStatus? = nil,
        wirelessVersion: Bool = true
    ) -> RobotSession {
        .preview(
            status: .preview(wirelessVersion: wirelessVersion),
            runningApp: runningApp,
            client: MaintenanceCapableClient(recorder: recorder)
        )
    }

    @Test("the section is offered only by a robot that mounts the routes")
    func offeredOnlyByAWirelessRobot() {
        #expect(session().canPerformMaintenance)
        #expect(!session(wirelessVersion: false).canPerformMaintenance)
        // A client that does not speak the protocol at all — every Lite robot and
        // every relay session.
        #expect(!RobotSession.preview().canPerformMaintenance)
    }

    /// The daemon deletes `/venvs/apps_venv/` without stopping anything first, so
    /// the interpreter a live app is running in goes away underneath it. Nothing
    /// on the robot prevents that; this is the only place it is prevented.
    @Test("a busy app blocks the uninstall", arguments: [
        RobotAppStatus.State.running,
        .starting,
        .stopping,
        .unknown("reloading"),
    ])
    func blocksWhileAnAppHoldsTheRobot(state: RobotAppStatus.State) {
        let status = RobotAppStatus.preview(state)

        #expect(MaintenanceModel().blockingApp(session(runningApp: status))?.name == status.app.name)
    }

    @Test("a finished or crashed app does not block it", arguments: [
        RobotAppStatus.State.done,
        .error,
    ])
    func allowsOnceTheAppIsOver(state: RobotAppStatus.State) {
        #expect(MaintenanceModel().blockingApp(session(runningApp: .preview(state))) == nil)
    }

    @Test("nothing running blocks nothing")
    func allowsWithNoApp() {
        #expect(MaintenanceModel().blockingApp(session()) == nil)
    }

    @Test("each action calls its own route and reports when it is done")
    func performsTheChosenAction() async {
        let recorder = MaintenanceRecorder()
        let session = session(recorder: recorder)
        let model = MaintenanceModel()

        await model.perform(.clearHuggingFaceCache, session: session)

        #expect(recorder.calls == ["clear-hf"])
        #expect(model.finished == .clearHuggingFaceCache)
        #expect(model.lastError == nil)
        #expect(!model.isBusy)

        await model.perform(.resetApps, session: session)

        #expect(recorder.calls == ["clear-hf", "reset-apps"])
        #expect(model.finished == .resetApps)
    }

    /// The failure belongs to this card, not to `RobotSession.robotError` — a
    /// maintenance call that refused says nothing about the robot's connection or
    /// its power.
    @Test("a refusal fills this card's own slot and claims nothing finished")
    func reportsARefusal() async {
        let recorder = MaintenanceRecorder()
        recorder.failure = Refused()
        let session = session(recorder: recorder)
        let model = MaintenanceModel()

        await model.perform(.resetApps, session: session)

        #expect(model.lastError == "The robot could not delete it.")
        #expect(model.finished == nil)
        #expect(session.robotError == nil)
        #expect(!model.isBusy)
    }
}
