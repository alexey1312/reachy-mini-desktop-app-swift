import ReachyKit
@testable import ReachyUI
import Testing

@MainActor
@Suite("Connection screen")
struct ConnectionScreenTests {
    private let identity = RobotIdentity.preview

    @Test("connection choices are enabled only while idle")
    func connectionChoicesFollowThePhase() {
        #expect(RobotSession.ConnectionPhase.idle.acceptsConnectionChoice)
        #expect(!RobotSession.ConnectionPhase.connecting(.handshaking).acceptsConnectionChoice)
        #expect(!RobotSession.ConnectionPhase.connecting(.checkingBackend(identity)).acceptsConnectionChoice)
        #expect(
            !RobotSession.ConnectionPhase.connecting(
                .backendUnavailable(identity, daemonMessage: nil)
            ).acceptsConnectionChoice
        )
        #expect(
            !RobotSession.ConnectionPhase.connecting(
                .failed(.connect, message: "offline")
            ).acceptsConnectionChoice
        )
        #expect(!RobotSession.ConnectionPhase.connected(identity).acceptsConnectionChoice)
        #expect(!RobotSession.ConnectionPhase.unreachable(identity).acceptsConnectionChoice)
    }
}
