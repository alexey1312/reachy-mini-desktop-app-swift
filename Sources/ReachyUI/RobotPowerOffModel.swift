import Foundation
import Observation
import ReachyKit

/// The one control on the Robot screen that needs asking twice.
///
/// A model rather than `@State` on the screen, for the reasons `MaintenanceModel`
/// records: the interesting part is the sentence in front of the button — which
/// app is about to be stopped — and that is worth asserting without rendering
/// anything. A preview can open the dialog too, which a `@State` bool cannot.
@MainActor
@Observable
final class RobotPowerOffModel {
    /// Not `private(set)`: the dialog's binding writes it back on dismissal.
    var isConfirming = false

    /// The app that powering off will take down with the backend.
    ///
    /// Not a reason to refuse, unlike `MaintenanceModel.blockingApp` — uninstalling
    /// deletes an environment out from under a live process, while this stops it
    /// first and on purpose. It is a reason to *say so*, because the reader may
    /// have left it running deliberately.
    ///
    /// An unfamiliar process state counts as running, the same way
    /// `RobotAppStatus.State.isBusy` treats it.
    func runningApp(_ session: RobotSession) -> RobotApp? {
        guard let status = session.runningApp, status.isBusy else { return nil }
        return status.app
    }

    /// Available on a LAN session only. `/api/daemon/stop` is an HTTP route, and the
    /// relay's command vocabulary has no equivalent — which is just as well, since
    /// tearing the backend down through a remote connection would leave nobody able
    /// to bring it back.
    func canPowerOff(_ session: RobotSession) -> Bool {
        session.address != nil && session.powerTransition == nil
    }

    func perform(_ session: RobotSession) async {
        await session.powerOff()
    }
}
