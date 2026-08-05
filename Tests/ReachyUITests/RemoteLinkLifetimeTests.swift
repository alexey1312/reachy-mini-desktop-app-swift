import ReachyKit
@testable import ReachyUI
import Testing

@Suite("Remote link lifetime")
struct RemoteLinkLifetimeTests {
    private let identity = RobotIdentity(
        hardwareID: "hw-1",
        name: "Reachy Mini",
        daemonVersion: "1.9.0"
    )

    @Test("a LAN session never retains a relay link")
    func releasesForLAN() {
        #expect(!RemoteLinkLifetime.shouldKeepAlive(
            isRemote: false,
            phase: .connected(identity)
        ))
    }

    @Test("recoverable remote phases retain the relay link")
    func retainsThroughRecoverablePhases() {
        let phases: [RobotSession.ConnectionPhase] = [
            .connecting(.handshaking),
            .connecting(.checkingBackend(identity)),
            .connecting(.backendUnavailable(identity, daemonMessage: nil)),
            .connected(identity),
            .unreachable(identity),
        ]

        for phase in phases {
            #expect(RemoteLinkLifetime.shouldKeepAlive(isRemote: true, phase: phase))
        }
    }

    @Test("terminal remote phases release the relay link")
    func releasesAfterTerminalPhases() {
        let update = DaemonUpdateRequirement(
            reported: "1.8.0",
            minimum: "1.9.0",
            canSelfUpdate: true
        )
        let phases: [RobotSession.ConnectionPhase] = [
            .idle,
            .connecting(.needsDaemonUpdate(identity, update)),
            .connecting(.failed(.backend, message: "offline")),
        ]

        for phase in phases {
            #expect(!RemoteLinkLifetime.shouldKeepAlive(isRemote: true, phase: phase))
        }
    }
}
