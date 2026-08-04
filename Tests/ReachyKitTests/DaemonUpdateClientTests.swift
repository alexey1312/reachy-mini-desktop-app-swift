import Foundation
@testable import ReachyKit
import Testing

/// `/update/*` is hand-written: it lives outside `/api`, exists only on a wireless
/// robot, and is absent from the committed spec, so nothing generated guards it.
@Suite("Daemon update client")
struct DaemonUpdateClientTests {
    private static func availability(current: String, latest: String, isAvailable: Bool) -> String {
        """
        {"update": {"reachy_mini": {"is_available": \(isAvailable),
         "current_version": "\(current)", "available_version": "\(latest)"}}}
        """
    }

    private func makeConnection(_ stubs: [String: StubURLProtocol.Stub]) throws -> RobotConnection {
        try RobotConnection(address: RobotAddress(host: "10.0.0.9"), session: StubURLProtocol.makeSession(stubs))
    }

    @Test("a newer release is reported with both versions")
    func reportsAvailableUpdate() async throws {
        let connection = try makeConnection([
            "/update/available": .init(
                statusCode: 200,
                json: Self.availability(current: "1.9.0", latest: "1.10.0", isAvailable: true)
            ),
        ])

        let availability = try await connection.availableUpdate(preRelease: false)

        #expect(availability == .available(current: "1.9.0", latest: "1.10.0"))
    }

    @Test("the beta channel is a separate question, so it reaches the daemon as a query item")
    func passesPreReleaseThrough() async throws {
        let connection = try makeConnection([
            "/update/available?pre_release=false": .init(
                statusCode: 200,
                json: Self.availability(current: "1.9.0", latest: "1.9.0", isAvailable: false)
            ),
            "/update/available?pre_release=true": .init(
                statusCode: 200,
                json: Self.availability(current: "1.9.0", latest: "1.10.0rc1", isAvailable: true)
            ),
        ])

        #expect(try await connection.availableUpdate(preRelease: false) == .upToDate(current: "1.9.0"))
        #expect(
            try await connection.availableUpdate(preRelease: true)
                == .available(current: "1.9.0", latest: "1.10.0rc1")
        )
    }

    @Test("an \"unknown\" available version means the robot has no internet, not that the check failed")
    func mapsUnknownVersionToRobotOffline() async throws {
        let connection = try makeConnection([
            "/update/available": .init(
                statusCode: 200,
                json: Self.availability(current: "1.9.0", latest: "unknown", isAvailable: false)
            ),
        ])

        #expect(try await connection.availableUpdate(preRelease: false) == .robotOffline(current: "1.9.0"))
    }

    @Test("a Lite robot never mounts the route, so its 404 is a capability answer")
    func mapsMissingRouteToUnavailable() async throws {
        let connection = try makeConnection(["/update/available": .init(statusCode: 404)])

        await #expect(throws: ReachyKitError.wirelessFeaturesUnavailable) {
            _ = try await connection.availableUpdate(preRelease: false)
        }
    }

    @Test("an update already running is the daemon's 400, not a missing feature")
    func surfacesUpdateInProgress() async throws {
        let connection = try makeConnection([
            "/update/start": .init(statusCode: 400, json: #"{"detail": "Update already in progress"}"#),
        ])

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 400)) {
            _ = try await connection.startUpdate(preRelease: false)
        }
    }

    @Test("starting an update yields the job id the log socket needs")
    func returnsJobID() async throws {
        let connection = try makeConnection([
            "/update/start": .init(statusCode: 200, json: #"{"job_id": "b3d1f0c2-0000-4000-8000-000000000000"}"#),
        ])

        #expect(try await connection.startUpdate(preRelease: true) == "b3d1f0c2-0000-4000-8000-000000000000")
    }

    @Test("an unknown job id keeps its 404 — only this route takes an identifier that can be absent")
    func keepsUnknownJob404() async throws {
        let connection = try makeConnection(["/update/info": .init(statusCode: 404)])

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 404)) {
            _ = try await connection.updateInfo(jobID: "nope")
        }
    }

    @Test("a job status this app has never heard of does not read as a failed update")
    func toleratesUnknownJobStatus() async throws {
        let connection = try makeConnection([
            "/update/info": .init(
                statusCode: 200,
                json: #"{"command": "update_reachy_mini", "status": "rebooting", "logs": ["one"]}"#
            ),
        ])

        let job = try await connection.updateInfo(jobID: "job")

        #expect(job.status == .unknown("rebooting"))
        #expect(job.status.isTerminal == false)
        #expect(job.logs == ["one"])
    }
}
