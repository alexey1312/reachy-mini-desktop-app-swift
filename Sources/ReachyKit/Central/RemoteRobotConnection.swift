import Foundation

/// The daemon, reached over a WebRTC session instead of over HTTP.
///
/// Deliberately a `RobotAPIClient` like `RobotConnection`, so `RobotSession` and
/// the screens above it do not have to know which way the robot was reached. It
/// is an honest subset, not a facade: everything the data channel does not carry
/// is left on the protocol's throwing defaults rather than stubbed out. Moves,
/// URDF, kinematics, the robot's own name and `/wifi`, `/update` are all
/// HTTP-only, and asking for them here fails rather than lies.
///
/// The command names and their fields are `reachy_mini/io/protocol.py`; the reply
/// shapes are `process_command` in `daemon/backend/abstract.py`.
public actor RemoteRobotConnection: RobotAPIClient {
    private let control: RemoteControlChannel
    /// No command answers the robot's name, so it comes from the central listing
    /// that got us to this robot — the same place the user picked it from.
    private let robotName: String?

    public init(control: RemoteControlChannel, robotName: String? = nil) {
        self.control = control
        self.robotName = robotName
    }

    public init(
        channel: any RemoteDataChannel,
        robotName: String? = nil,
        timeout: Duration = .seconds(10)
    ) {
        self.init(
            control: RemoteControlChannel(channel: channel, timeout: timeout),
            robotName: robotName
        )
    }

    public func handshake() async throws -> RobotConnection.Handshake {
        let status = try await daemonStatus()
        return RobotConnection.Handshake(
            identity: RobotIdentity(
                hardwareID: status.hardwareId,
                name: robotName,
                daemonVersion: status.version
            ),
            status: status,
            // Renaming is `POST /api/daemon/robot-name` and no command on this
            // channel carries it, so the field is greyed out rather than left to
            // fail on save.
            supportsRename: false
        )
    }

    /// Assembled rather than fetched. The daemon publishes `daemon_status` once a
    /// second, but only to its WebSocket clients — `Daemon._publish_status` calls
    /// `ws_server.publish_status`, not `broadcast_to_all_clients` — so it never
    /// reaches the data channel and there is no command that asks for it.
    ///
    /// Every field below is either read off the channel, carried in from central,
    /// or a value that *closes* a feature rather than opening one:
    ///
    /// - `state` is `.running` because the data-channel handler is installed on
    ///   the backend (`setup_media_server`); a reply proves the backend is up.
    /// - `wirelessVersion` is `false` because it gates `/wifi/*` and `/update/*`,
    ///   HTTP routes on the robot's own network that this session genuinely
    ///   cannot reach.
    /// - `backendStatus` stays `nil`: unknown, and said so.
    public func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        let version = try await control.perform(
            "get_version",
            correlation: .replyKey("version"),
            expecting: VersionReply.self
        )
        let hardware = try await control.perform(
            "get_hardware_id",
            correlation: .replyKey("hardware_id"),
            expecting: HardwareIDReply.self
        )
        return Components.Schemas.DaemonStatus(
            robotName: robotName ?? "",
            state: .running,
            wirelessVersion: false,
            desktopAppDaemon: false,
            version: version.version,
            hardwareId: hardware.hardwareID
        )
    }

    /// The channel answers `wake_up` only once the animation has finished, so
    /// there is no id to track and nothing to poll — see `runningMoveUUIDs`.
    public func wakeUp() async throws -> String {
        try await control.perform("wake_up")
        return ""
    }

    public func gotoSleep() async throws -> String {
        try await control.perform("goto_sleep")
        return ""
    }

    /// Empty, always, and not a guess: this connection never hands out a move id,
    /// so the set of moves it could be waiting on is empty by construction. That
    /// is what lets `RobotSession.waitForMoveToFinish` return at once instead of
    /// sitting out its whole timeout on a move that finished before it was told.
    public func runningMoveUUIDs() async throws -> Set<String> {
        []
    }

    public func setMotorMode(_ mode: Components.Schemas.MotorControlMode) async throws {
        try await control.perform(
            "set_motor_mode",
            payload: ["mode": .string(mode.rawValue)],
            correlation: .replyKey("motor_mode")
        )
    }

    public func volume() async throws -> AudioLevel {
        try await level(from: control.perform("get_volume", expecting: VolumeReply.self))
    }

    /// The daemon answers with the level it settled on, which is not the one asked
    /// for when the platform refused it — so the reply is read, not assumed.
    public func setVolume(_ percent: Int) async throws -> AudioLevel {
        try await level(from: control.perform(
            "set_volume",
            payload: ["volume": .number(Double(percent))],
            expecting: VolumeReply.self
        ))
    }

    public func microphoneVolume() async throws -> AudioLevel {
        try await level(from: control.perform("get_microphone_volume", expecting: VolumeReply.self))
    }

    public func setMicrophoneVolume(_ percent: Int) async throws -> AudioLevel {
        try await level(from: control.perform(
            "set_microphone_volume",
            payload: ["volume": .number(Double(percent))],
            expecting: VolumeReply.self
        ))
    }

    /// The channel reports a level and nothing else, where the REST route also
    /// names the sink it moved.
    private func level(from reply: VolumeReply) -> AudioLevel {
        AudioLevel(percent: reply.volume)
    }

    private struct VersionReply: Decodable {
        let version: String
    }

    private struct HardwareIDReply: Decodable {
        let hardwareID: String

        enum CodingKeys: String, CodingKey {
            case hardwareID = "hardware_id"
        }
    }

    private struct VolumeReply: Decodable {
        let volume: Int
    }
}
