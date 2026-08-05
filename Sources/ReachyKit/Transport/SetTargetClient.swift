import Foundation

/// Live teleop: streams `FullBodyTarget` frames to `ws://…/api/move/ws/set_target`.
///
/// The daemon clamps all safety limits server-side and ignores targets while a
/// recorded move is running — this client just ships raw targets. Sends are
/// throttled to `minSendInterval` (latest wins); the server's error replies are
/// drained and kept in `lastServerError`.
public actor SetTargetClient {
    public static let path = "/api/move/ws/set_target"

    /// The target moved to `TeleopTarget` when the data channel grew a second way
    /// to send one. Kept as a name so the screens and tests that spell it this way
    /// are unchanged.
    public typealias Target = TeleopTarget

    public private(set) var lastServerError: String?

    private let url: URL
    private let session: URLSession
    private let minSendInterval: Duration
    private var socket: URLSessionWebSocketTask?
    private var drainTask: Task<Void, Never>?
    private var lastSendAt: ContinuousClock.Instant?

    public init(
        address: RobotAddress,
        minSendInterval: Duration = .milliseconds(33),
        session: URLSession = .shared
    ) throws {
        guard let url = address.webSocketURL(path: Self.path) else {
            throw ReachyKitError.invalidAddress(address)
        }
        self.url = url
        self.session = session
        self.minSendInterval = minSendInterval
    }

    public func connect() {
        guard socket == nil else { return }
        let socket = session.webSocketTask(with: url)
        socket.resume()
        self.socket = socket
        drainTask = Task { [weak self] in
            while let self, let socket = await self.socket {
                guard let message = try? await socket.receive() else { break }
                if case let .string(text) = message {
                    await record(serverError: text)
                }
            }
        }
    }

    public func disconnect() {
        drainTask?.cancel()
        drainTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Sends a target; drops the frame if the previous send was under
    /// `minSendInterval` ago (the UI emits at gesture rate, the wire shouldn't).
    public func send(_ target: Target) async {
        guard let socket else { return }
        let now = ContinuousClock.now
        if let lastSendAt, lastSendAt.duration(to: now) < minSendInterval {
            return
        }
        lastSendAt = now
        guard let text = String(bytes: Self.encode(target), encoding: .utf8) else { return }
        try? await socket.send(.string(text))
    }

    private func record(serverError text: String) {
        lastServerError = text
    }

    /// Wire format: `FullBodyTarget` JSON, head pose as flat XYZRPY.
    static func encode(_ target: Target) -> Data {
        let payload: [String: Any] = [
            "target_head_pose": [
                "x": target.x, "y": target.y, "z": target.z,
                "roll": target.roll, "pitch": target.pitch, "yaw": target.yaw,
            ],
            "target_antennas": [target.antennaLeft, target.antennaRight],
            "target_body_yaw": target.bodyYaw,
        ]
        // ponytail: JSONSerialization over generated FullBodyTarget — the anyOf
        // head-pose payload encodes asymmetrically; a flat dict is the wire truth
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

/// Every requirement is already satisfied verbatim — an actor's isolated method
/// meets an `async` one.
extension SetTargetClient: TeleopChannel {}

extension RobotConnection: TeleopClient {
    public nonisolated func makeTeleop() throws -> any TeleopChannel {
        try SetTargetClient(address: address)
    }
}
