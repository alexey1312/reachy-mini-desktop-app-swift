import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// Owns the HTTP client for one robot daemon and performs the connection handshake.
///
/// The handshake establishes robot identity (hardware id, display name) and daemon
/// version before anything else — the version drives graceful degradation, and the
/// hardware id is the only safe way to deduplicate robots seen at several addresses.
public actor RobotConnection {
    public let address: RobotAddress
    private let client: Client
    /// The readiness probe reads a status code, never a body, so it deliberately
    /// bypasses the generated client. It also gets upstream's 10 s budget rather
    /// than the 3.5 s tuned for the 3 s status poll.
    private let readinessSession: URLSession
    /// Mesh downloads run to tens of megabytes; the 3.5 s health-poll budget would
    /// abort them, so they get their own session.
    private let assetSession: URLSession

    public init(address: RobotAddress, session: URLSession? = nil) throws {
        guard let serverURL = address.rootURL else {
            throw ReachyKitError.invalidAddress(address)
        }
        self.address = address

        func makeSession(timeout: TimeInterval, resourceTimeout: TimeInterval? = nil) -> URLSession {
            // An injected session belongs to a test harness — reuse it so stubbed
            // protocols still intercept every request.
            if let session {
                return session
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            if let resourceTimeout {
                configuration.timeoutIntervalForResource = resourceTimeout
            }
            return URLSession(configuration: configuration)
        }

        client = Client(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: makeSession(timeout: 3.5)))
        )
        readinessSession = makeSession(timeout: 10)
        assetSession = makeSession(timeout: 20, resourceTimeout: 120)
    }

    /// Result of a successful handshake with the daemon.
    public struct Handshake: Sendable {
        public let identity: RobotIdentity
        public let status: Components.Schemas.DaemonStatus
        public let compatibility: DaemonCompatibility

        public init(
            identity: RobotIdentity,
            status: Components.Schemas.DaemonStatus,
            compatibility: DaemonCompatibility? = nil
        ) {
            self.identity = identity
            self.status = status
            self.compatibility = compatibility ?? DaemonCompatibilityPolicy.evaluate(identity.daemonVersion)
        }
    }

    public func handshake() async throws -> Handshake {
        let status = try await daemonStatus()
        let compatibility = DaemonCompatibilityPolicy.evaluate(status.version)
        if case let .unsupported(reported, minimum) = compatibility {
            throw ReachyKitError.unsupportedDaemonVersion(reported: reported, minimum: minimum)
        }

        // hardware-id returns a string map (component serials); flatten deterministically
        // so the same robot always yields the same identity string. The simulated daemon
        // returns null values here, which the generated [String: String] map rejects —
        // treat that as "no hardware id" rather than a failed handshake.
        let hardwareMap = try? await client.getRobotHardwareIdApiDaemonHardwareIdGet()
            .ok.body.json.additionalProperties
        let hardwareID = hardwareMap.flatMap { map -> String? in
            map.isEmpty ? nil : map
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ";")
        }

        let name = try? await client.getRobotDisplayNameApiDaemonRobotNameGet().ok.body.json.name

        return Handshake(
            identity: RobotIdentity(
                hardwareID: hardwareID,
                name: name ?? status.robotName,
                daemonVersion: status.version
            ),
            status: status,
            compatibility: compatibility
        )
    }

    /// One-shot full state via REST — fallback only; prefer `StateStreamClient`.
    public func fullState() async throws -> Components.Schemas.FullState {
        switch try await client.getFullStateApiStateFullGet() {
        case let .ok(response):
            return try response.body.json
        case .unprocessableContent:
            throw ReachyKitError.daemonRejected(statusCode: 422)
        case let .undocumented(statusCode, _):
            throw ReachyKitError.fromStatusCode(statusCode)
        }
    }

    /// The readiness gate. `daemonStatus().state == .running` flips before the
    /// backend finishes coming up; this route is guarded by the daemon's
    /// `get_backend`, which answers 503 until `backend.ready` is set — so a 200
    /// here is the first honest "the robot can be driven" signal.
    ///
    /// Only the status code carries that signal, so the body is never decoded:
    /// going through the generated client made readiness depend on whether our
    /// schema could parse the payload, and a live daemon serves `last_alive` in a
    /// format the generated ISO-8601 date decoder rejects — a ready robot then
    /// looked like a failed connection.
    public func probeBackendReady() async throws {
        guard let url = address.httpURL(path: "/api/state/full") else {
            throw ReachyKitError.invalidAddress(address)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (_, response) = try await readinessSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReachyKitError.daemonRejected(statusCode: -1)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ReachyKitError.fromStatusCode(http.statusCode)
        }
    }

    public func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        switch try await client.getDaemonStatusApiDaemonStatusGet() {
        case let .ok(response):
            return try response.body.json
        case let .undocumented(statusCode, _):
            throw ReachyKitError.fromStatusCode(statusCode)
        }
    }

    /// Plays the wake-up animation. Motors must already be enabled — the daemon
    /// route does not touch the control mode, so a `disabled` robot just doesn't move.
    ///
    /// Status codes are mapped explicitly: `.ok` would surface the daemon's 503
    /// "Backend not running" as an opaque `undocumented` runtime error.
    public func wakeUp() async throws -> String {
        switch try await client.playWakeUpApiMovePlayWakeUpPost() {
        case let .ok(response):
            return try response.body.json.uuid
        case let .undocumented(statusCode, _):
            throw ReachyKitError.fromStatusCode(statusCode)
        }
    }

    public func gotoSleep() async throws -> String {
        switch try await client.playGotoSleepApiMovePlayGotoSleepPost() {
        case let .ok(response):
            return try response.body.json.uuid
        case let .undocumented(statusCode, _):
            throw ReachyKitError.fromStatusCode(statusCode)
        }
    }

    public func setMotorMode(_ mode: Components.Schemas.MotorControlMode) async throws {
        switch try await client.setMotorModeApiMotorsSetModeModePost(path: .init(mode: mode)) {
        case .ok:
            return
        case .unprocessableContent:
            throw ReachyKitError.daemonRejected(statusCode: 422)
        case let .undocumented(statusCode, _):
            throw ReachyKitError.fromStatusCode(statusCode)
        }
    }

    public func motorMode() async throws -> Components.Schemas.MotorControlMode {
        try await client.getMotorStatusApiMotorsStatusGet().ok.body.json.mode
    }

    /// Starts the robot backend. Returns immediately with a job id — the caller
    /// must poll `daemonStatus()` until the state settles.
    public func startDaemon(wakeUp: Bool) async throws {
        switch try await client.startDaemonApiDaemonStartPost(query: .init(wakeUp: wakeUp)) {
        case .ok:
            return
        case .unprocessableContent:
            throw ReachyKitError.daemonRejected(statusCode: 422)
        case let .undocumented(statusCode, _):
            throw ReachyKitError.fromStatusCode(statusCode)
        }
    }

    // MARK: Recorded moves (dances / emotions / music libraries)

    /// Move names available in a HF dataset, e.g. `pollen-robotics/reachy-mini-dances-library`.
    public func listMoves(dataset: String) async throws -> [String] {
        try await client.listRecordedMoveDatasetApiMoveRecordedMoveDatasetsListDatasetNameGet(
            path: .init(datasetName: dataset)
        ).ok.body.json
    }

    /// Starts a recorded move; returns its UUID for `stopMove`.
    public func playMove(dataset: String, move: String) async throws -> String {
        try await client.playRecordedMoveDatasetApiMovePlayRecordedMoveDatasetDatasetNameMoveNamePost(
            path: .init(datasetName: dataset, moveName: move)
        ).ok.body.json.uuid
    }

    /// Authoritative daemon view of tasks still running, used to detect natural completion.
    public func runningMoveUUIDs() async throws -> Set<String> {
        let moves = try await client.getRunningMovesApiMoveRunningGet().ok.body.json
        return Set(moves.map(\.uuid))
    }

    public func stopMove(uuid: String) async throws {
        _ = try await client.stopMoveApiMoveStopPost(body: .json(.init(uuid: uuid))).ok
    }

    /// Recorded music is owned by the daemon's media player, separately from the move task.
    public func stopSound() async throws {
        _ = try await client.stopSoundApiMediaStopSoundPost().ok
    }

    /// The robot's own URDF, about 250 KB of XML wrapped in a one-key JSON object.
    /// Geometry comes from the robot rather than the app bundle, so the model
    /// always matches the machine in front of the user.
    public func urdf() async throws -> String {
        let payload = try await client.getUrdfApiKinematicsUrdfGet().ok.body.json.additionalProperties
        guard let xml = payload["urdf"], !xml.isEmpty else {
            throw ReachyKitError.daemonRejected(statusCode: 200)
        }
        return xml
    }

    /// A mesh referenced by the URDF, as raw bytes.
    ///
    /// The generated client cannot fetch this: it declares `application/json` for
    /// every response and sends a matching `Accept`, while the daemon answers
    /// `model/stl` — the runtime rejects the reply before reading a byte.
    public func stlAsset(named filename: String) async throws -> Data {
        guard let url = address.httpURL(path: "/api/kinematics/stl/\(filename)") else {
            throw ReachyKitError.invalidAddress(address)
        }
        let (data, response) = try await assetSession.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw ReachyKitError.fromStatusCode(http.statusCode)
        }
        guard !data.isEmpty else {
            throw URLError(.zeroByteResource)
        }
        return data
    }

    /// Which kinematics engine the daemon runs — the one thing that decides
    /// whether `passive_joints` ever arrives populated.
    public func kinematicsInfo() async throws -> KinematicsInfo {
        let container = try await client.getKinematicsInfoApiKinematicsInfoGet().ok.body.json
        let data = try JSONEncoder().encode(container)
        return try JSONDecoder().decode(KinematicsInfo.self, from: data)
    }

    /// Re-acquires camera/audio hardware for the daemon's WebRTC producer.
    /// The simulator registers no producer until this is called; on a real
    /// robot it's a harmless no-op when media is already held.
    public func acquireMedia() async throws {
        _ = try await client.acquireMediaApiMediaAcquirePost().ok
    }
}
