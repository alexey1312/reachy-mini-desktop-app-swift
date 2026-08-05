import Foundation
@testable import ReachyKit
import ReachyTestSupport
import Testing

@Suite("RobotReachability", .timeLimit(.minutes(1)))
struct RobotReachabilityTests {
    private let address = RobotAddress(host: "10.0.0.9")

    @Test("a daemon answering the hardware-id route is reachable")
    func reachable() async {
        let session = StubURLProtocol.makeSession([
            "/api/daemon/hardware-id": .init(statusCode: 200, json: #"{"hardware_id":"b68ff6bbe47f0608"}"#),
        ])

        #expect(await RobotReachability.probe(address, session: session))
    }

    @Test("a server error means the robot is not usable")
    func serverError() async {
        let session = StubURLProtocol.makeSession([
            "/api/daemon/hardware-id": .init(statusCode: 500),
        ])

        #expect(await !RobotReachability.probe(address, session: session))
    }

    @Test("nothing listening reads as unreachable rather than throwing")
    func refused() async {
        // Port 1 on loopback: no stub protocol, so this is a real refused connection.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2

        let unreachable = await RobotReachability.probe(
            RobotAddress(host: "127.0.0.1", port: 1),
            session: URLSession(configuration: configuration)
        )
        #expect(!unreachable)
    }
}
