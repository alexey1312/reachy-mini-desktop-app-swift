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

    public init(address: RobotAddress, session: URLSession? = nil) throws {
        guard let serverURL = address.rootURL else {
            throw ReachyKitError.invalidAddress(address)
        }
        self.address = address

        let resolvedSession: URLSession
        if let session {
            resolvedSession = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 3.5
            resolvedSession = URLSession(configuration: configuration)
        }
        client = Client(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: resolvedSession))
        )
    }

    /// Result of a successful handshake with the daemon.
    public struct Handshake: Sendable {
        public let identity: RobotIdentity
        public let status: Components.Schemas.DaemonStatus
    }

    public func handshake() async throws -> Handshake {
        let status = try await client.getDaemonStatusApiDaemonStatusGet().ok.body.json

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
            status: status
        )
    }

    /// One-shot full state via REST — fallback only; prefer `StateStreamClient`.
    public func fullState() async throws -> Components.Schemas.FullState {
        try await client.getFullStateApiStateFullGet().ok.body.json
    }

    public func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        try await client.getDaemonStatusApiDaemonStatusGet().ok.body.json
    }

    public func wakeUp() async throws {
        _ = try await client.playWakeUpApiMovePlayWakeUpPost().ok
    }

    public func gotoSleep() async throws {
        _ = try await client.playGotoSleepApiMovePlayGotoSleepPost().ok
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
}
