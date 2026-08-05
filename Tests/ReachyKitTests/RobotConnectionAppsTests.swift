import Foundation
@testable import ReachyKit
import ReachyTestSupport
import Testing

/// The app store surface of `/api/apps/*`. Every quirk asserted here is one the
/// daemon's own router (`daemon/app/routers/apps.py`) produces.
@Suite("Apps over HTTP", .timeLimit(.minutes(1)))
struct RobotConnectionAppsTests {
    private func makeSession(_ stubs: [String: StubURLProtocol.Stub]) -> URLSession {
        StubURLProtocol.makeSession(stubs)
    }

    private func makeConnection(_ session: URLSession) throws -> RobotConnection {
        try RobotConnection(address: RobotAddress(host: "10.42.0.1"), session: session)
    }

    private static let catalogue = #"""
    [
      {
        "name": "reachy-mini-dance",
        "source_kind": "hf_space",
        "description": "Make the robot dance",
        "url": "https://huggingface.co/spaces/pollen-robotics/reachy-mini-dance",
        "extra": {"id": "pollen-robotics/reachy-mini-dance", "author": "pollen-robotics", "likes": 42}
      }
    ]
    """#

    @Test("lists the catalogue with its Space cards intact")
    func listsAvailableApps() async throws {
        let session = makeSession(["/api/apps/list-available": .init(statusCode: 200, json: Self.catalogue)])

        let apps = try await makeConnection(session).availableApps()

        #expect(apps.count == 1)
        #expect(apps.first?.spaceID == "pollen-robotics/reachy-mini-dance")
        #expect(apps.first?.likes == 42)
    }

    @Test("asks for one source kind by name")
    func listsInstalledApps() async throws {
        let session = makeSession([
            "/api/apps/list-available/installed": .init(
                statusCode: 200,
                json: #"[{"name": "dance_party", "source_kind": "installed", "extra": {}}]"#
            ),
        ])

        let apps = try await makeConnection(session).installedApps()

        #expect(apps.map(\.name) == ["dance_party"])
    }

    /// `current_app_status` is typed `AppStatus | None`, and the normalizer that
    /// prepares the spec for the generator drops the null branch — so an idle robot
    /// answers **200 with a literal `null`** that the generated model cannot parse.
    /// Reading it as "nothing is running" is the whole point of this route.
    @Test("an idle robot answers 200 with a literal null")
    func idleRobotHasNoCurrentApp() async throws {
        let session = makeSession(["/api/apps/current-app-status": .init(statusCode: 200, json: "null")])

        #expect(try await makeConnection(session).currentAppStatus() == nil)
    }

    @Test("a busy robot names the app holding it")
    func reportsCurrentApp() async throws {
        let session = makeSession([
            "/api/apps/current-app-status": .init(
                statusCode: 200,
                json: #"""
                {"info": {"name": "dance_party", "source_kind": "installed", "extra": {}}, "state": "running"}
                """#
            ),
        ])

        let status = try await makeConnection(session).currentAppStatus()

        #expect(status?.app.name == "dance_party")
        #expect(status?.state == .running)
    }

    /// The daemon files the posted `AppInfo` away as the app's stored metadata, so
    /// what goes over the wire has to be the catalogue entry byte for byte —
    /// anything this client re-shapes is lost on the robot for good.
    @Test("install posts the catalogue entry back verbatim")
    func installSendsTheWholeAppInfo() async throws {
        let session = makeSession(["/api/apps/install": .init(statusCode: 200, json: #"{"job_id": "job-1"}"#)])
        let app = try JSONDecoder().decode([RobotApp].self, from: Data(Self.catalogue.utf8))[0]

        let jobID = try await makeConnection(session).installApp(app)

        #expect(jobID == "job-1")
        let body = try #require(StubURLProtocol.bodies(for: session).first)
        let sent = try JSONSerialization.jsonObject(with: body) as? NSDictionary
        let original = try JSONSerialization.jsonObject(with: Data(Self.catalogue.utf8)) as? [NSDictionary]
        #expect(sent == original?.first)
    }

    /// `install` refuses anything but a Space with a 400 the spec never mentions,
    /// so it arrives as an undocumented status rather than a typed case.
    @Test("installing a non-Space is refused, not retried")
    func installRejectsNonSpaceSources() async throws {
        let refusal = StubURLProtocol.Stub(statusCode: 400, json: #"{"detail": "not installable"}"#)
        let session = makeSession(["/api/apps/install": refusal])
        let app = try JSONDecoder().decode(RobotApp.self, from: Data(#"""
        {"name": "local-thing", "source_kind": "local", "extra": {}}
        """#.utf8))

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 400)) {
            try await makeConnection(session).installApp(app)
        }
    }

    /// Installing from a private Space is its own route: the daemon builds the
    /// `AppInfo` itself and needs its stored Hugging Face token to fetch anything,
    /// answering 401 when none was saved.
    @Test("a private Space install needs the robot to be linked")
    func privateInstallNeedsAToken() async throws {
        let session = makeSession(["/api/apps/install-private-space": .init(statusCode: 401)])

        await #expect(throws: ReachyKitError.self) {
            try await makeConnection(session).installPrivateSpace(id: "someone/secret")
        }
    }

    @Test("removing an app returns the job that does it")
    func removeReturnsJob() async throws {
        let session = makeSession([
            "/api/apps/remove/dance_party": .init(statusCode: 200, json: #"{"job_id": "job-2"}"#),
        ])

        #expect(try await makeConnection(session).removeApp(named: "dance_party") == "job-2")
    }

    /// A job id does not survive the daemon restarting: the register is in memory,
    /// so a 404 here means the job is gone, not that the route is missing.
    @Test("a job the daemon has forgotten reads as 404")
    func forgottenJobIs404() async throws {
        let session = makeSession(["/api/apps/job-status/job-1": .init(statusCode: 404)])

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 404)) {
            try await makeConnection(session).appJob(id: "job-1")
        }
    }

    @Test("a running job reports its logs so far")
    func readsJobProgress() async throws {
        let session = makeSession([
            "/api/apps/job-status/job-1": .init(
                statusCode: 200,
                json: #"{"command": "install", "status": "in_progress", "logs": ["Collecting reachy-mini"]}"#
            ),
        ])

        let job = try await makeConnection(session).appJob(id: "job-1")

        #expect(job.status == .inProgress)
        #expect(job.logs == ["Collecting reachy-mini"])
    }

    /// Stopping when nothing runs is a 400, and the screen has to say so rather
    /// than show a failure the user cannot act on.
    @Test("stopping twice is refused the second time")
    func stopIsRefusedWhenNothingRuns() async throws {
        let session = makeSession(["/api/apps/stop-current-app": .init(statusCode: 400)])

        await #expect(throws: ReachyKitError.daemonRejected(statusCode: 400)) {
            try await makeConnection(session).stopCurrentApp()
        }
    }

    @Test("starting an app returns the status it started in")
    func startReturnsStatus() async throws {
        let session = makeSession([
            "/api/apps/start-app/dance_party": .init(
                statusCode: 200,
                json: #"""
                {"info": {"name": "dance_party", "source_kind": "installed", "extra": {}}, "state": "starting"}
                """#
            ),
        ])

        let status = try await makeConnection(session).startApp(named: "dance_party")

        #expect(status.state == .starting)
        #expect(status.isBusy)
    }

    @Test("the startup app is null until one is chosen")
    func readsStartupApp() async throws {
        let session = makeSession(["/api/apps/startup-app": .init(statusCode: 200, json: #"{"startup_app": null}"#)])

        #expect(try await makeConnection(session).startupApp() == nil)
    }

    /// Clearing is a PUT that names no app — Pydantic reads an absent key and an
    /// explicit null identically, so the assertion is on the name being gone
    /// rather than on which of the two spellings the encoder chose.
    @Test("clearing the startup app names no app")
    func clearsStartupApp() async throws {
        let session = makeSession(["/api/apps/startup-app": .init(statusCode: 200, json: #"{"startup_app": null}"#)])

        _ = try await makeConnection(session).setStartupApp(nil)

        let request = try #require(StubURLProtocol.requests(for: session).first)
        #expect(request.httpMethod == "PUT")
        let body = try #require(StubURLProtocol.bodies(for: session).first)
        let named = try (JSONSerialization.jsonObject(with: body) as? [String: Any])?["startup_app"]
        #expect(named == nil || named is NSNull)
    }

    @Test("a remote session holds the robot just as a local app does")
    func readsLockStatus() async throws {
        let session = makeSession([
            "/api/daemon/robot-app-lock-status": .init(
                statusCode: 200,
                json: #"{"state": "remote_session", "holder_name": "alexey1312"}"#
            ),
        ])

        let lock = try await makeConnection(session).appLockStatus()

        #expect(lock.state == .remoteSession)
        #expect(lock.holderName == "alexey1312")
    }

    @Test("the update check reports what it could not check")
    func checksUpdates() async throws {
        let session = makeSession([
            "/api/apps/check-updates?force=true": .init(
                statusCode: 200,
                json: #"{"apps_with_updates": [], "apps_checked": 2, "apps_skipped": 1}"#
            ),
        ])

        let summary = try await makeConnection(session).appUpdates(force: true)

        #expect(summary.isEmpty)
        #expect(summary.checked == 2)
        #expect(summary.skipped == 1)
    }
}
