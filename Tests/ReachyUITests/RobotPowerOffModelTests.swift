import Foundation
import ReachyKit
@testable import ReachyUI
import Testing

@MainActor
@Suite("Power off")
struct RobotPowerOffModelTests {
    @Test("names the app the shutdown will take with it")
    func namesTheRunningApp() {
        let model = RobotPowerOffModel()
        let session = RobotSession.preview(runningApp: .preview(.running))
        #expect(model.runningApp(session)?.name == RobotAppStatus.preview(.running).app.name)
    }

    @Test("says nothing about an app that has already finished")
    func ignoresAFinishedApp() {
        let model = RobotPowerOffModel()
        #expect(model.runningApp(RobotSession.preview(runningApp: .preview(.done))) == nil)
        #expect(model.runningApp(RobotSession.preview(runningApp: .previewCrashed)) == nil)
        #expect(model.runningApp(RobotSession.preview()) == nil)
    }

    /// The same reading `RobotAppStatus.State.isBusy` takes: a state this client
    /// does not recognise still holds the robot, so it is still worth naming.
    @Test("an unfamiliar process state still counts as running")
    func unknownStateCountsAsRunning() {
        let model = RobotPowerOffModel()
        let status = RobotAppStatus(app: RobotApp.previewInstalled[0], state: .unknown("pausing"))
        #expect(model.runningApp(RobotSession.preview(runningApp: status)) != nil)
    }

    @Test("offered on a LAN session only — the relay has no route to the daemon's own stop")
    func relaySessionCannotPowerOff() {
        let model = RobotPowerOffModel()
        #expect(model.canPowerOff(RobotSession.preview()))
        #expect(!model.canPowerOff(RobotSession.preview(address: nil, link: .remote)))
    }

    @Test("declines a second tap while a transition is running")
    func busyDuringATransition() {
        let model = RobotPowerOffModel()
        #expect(!model.canPowerOff(RobotSession.preview(powerTransition: .stoppingBackend)))
        #expect(!model.canPowerOff(RobotSession.preview(powerTransition: .goingToSleep)))
    }
}
