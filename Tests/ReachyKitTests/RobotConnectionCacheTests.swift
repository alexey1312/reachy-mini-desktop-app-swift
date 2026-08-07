import Foundation
@testable import ReachyKit
import ReachyTestSupport
import Testing

/// `/cache/*` mounts at the app root and only under `--wireless-version`, like
/// `/wifi/*` and `/update/*`, so it is absent from the committed OpenAPI spec and
/// `sim-daemon` cannot serve it either. Stubs and real hardware are the whole of
/// the coverage.
@Suite("Cache maintenance over HTTP")
struct RobotConnectionCacheTests {
    private func makeConnection(_ session: URLSession) throws -> RobotConnection {
        try RobotConnection(address: RobotAddress(host: "10.42.0.1"), session: session)
    }

    /// The path carries no `/api` prefix. Getting that wrong is the one mistake
    /// these two routes invite, and it would 404 — which this client reads as a
    /// Lite robot rather than as a typo.
    @Test("clearing the Hugging Face cache POSTs to the root-mounted route")
    func clearsTheHuggingFaceCache() async throws {
        let session = StubURLProtocol.makeSession([
            "/cache/clear-hf": .init(
                statusCode: 200,
                json: #"{"status":"success","message":"HuggingFace cache cleared"}"#
            ),
        ])

        try await makeConnection(session).clearHuggingFaceCache()

        let request = StubURLProtocol.requests(for: session).first
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/cache/clear-hf")
    }

    @Test("uninstalling every app POSTs to reset-apps")
    func resetsApps() async throws {
        let session = StubURLProtocol.makeSession([
            "/cache/reset-apps": .init(
                statusCode: 200,
                json: #"{"status":"success","message":"Applications virtual environment removed"}"#
            ),
        ])

        try await makeConnection(session).resetApps()

        let request = StubURLProtocol.requests(for: session).first
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/cache/reset-apps")
    }

    /// The daemon answers 200 with a different `message` when the directory was
    /// already gone. Both are success, and the client drops the sentence rather
    /// than putting the daemon's English on a screen it cannot translate.
    @Test("an already-empty directory is a success, not a failure")
    func acceptsAnAlreadyEmptyDirectory() async throws {
        let session = StubURLProtocol.makeSession([
            "/cache/reset-apps": .init(
                statusCode: 200,
                json: #"{"status":"success","message":"Virtual environment directory already empty"}"#
            ),
        ])

        try await makeConnection(session).resetApps()
    }

    /// A Lite robot never mounts the router, so 404 here means the feature is
    /// absent rather than the resource — the same reading `/wifi/*` gets.
    @Test("a Lite robot's 404 reports the feature as unavailable")
    func reportsAnUnmountedRouterAsUnavailable() async throws {
        let session = StubURLProtocol.makeSession(["/cache/clear-hf": .init(statusCode: 404)])
        let connection = try makeConnection(session)

        await #expect(throws: ReachyKitError.wirelessFeaturesUnavailable) {
            try await connection.clearHuggingFaceCache()
        }
    }

    /// `shutil.rmtree` failing comes back as a 500 with a `detail`, which is the
    /// only way the robot reports that it could not delete something.
    @Test("a failed delete surfaces as a rejection")
    func surfacesAFailedDelete() async throws {
        let session = StubURLProtocol.makeSession([
            "/cache/reset-apps": .init(statusCode: 500, json: #"{"detail":"Failed to clear virtual environment"}"#),
        ])
        let connection = try makeConnection(session)

        await #expect(throws: (any Error).self) {
            try await connection.resetApps()
        }
    }
}
