import Foundation

/// The WebRTC data channel, with the WebRTC left out.
///
/// A seam rather than an `RTCDataChannel`: the protocol above it is plain JSON
/// and belongs with the rest of the daemon's vocabulary, in a module that does
/// not link a media framework.
public protocol RemoteDataChannel: Sendable {
    func send(_ text: String) async throws
    func messages() -> AsyncStream<String>
    /// Whether a command sent now would go out, rather than wait for a channel the
    /// robot has not opened yet. Deliberately the same question `send` asks itself
    /// before deciding to wait — a caller bounding that wait has to bound the same
    /// thing, or it is timing something other than what is happening.
    var isOpen: Bool { get }
}

/// A JSON value, for command payloads whose shape the caller decides.
public enum RemoteValue: Equatable, Sendable, Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([RemoteValue])
    case object([String: RemoteValue])
    case null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case let .object(values): try container.encode(values)
        case .null: try container.encodeNil()
        }
    }
}

/// Drives the robot over the reliable `"data"` channel of a WebRTC session.
///
/// This is the whole control surface of a remote session: the daemon's HTTP API
/// is not reachable from outside the robot's network, and the same commands
/// arrive here as JSON instead.
///
/// **There is no request id.** Most commands are answered by echoing the name
/// back — `{"status": "ok", "command": "wake_up", "completed": true}`, or
/// `{"error": "…", "command": "wake_up"}` — but a handful answer with the bare
/// payload and no name at all: `get_version` sends `{"version": …}`,
/// `get_hardware_id` sends `{"hardware_id": …}`, `get_state` sends `{"state": …}`
/// and both motor-mode commands send `{"motor_mode": …}`. A reply can therefore
/// only be attributed by something the caller supplies, which is what
/// `Correlation` is. Two commands sharing a token are serialised rather than
/// guessed at.
public actor RemoteControlChannel {
    /// How a command's reply is recognised on a channel that carries no ids.
    public enum Correlation: Sendable, Equatable {
        /// The reply echoes the command name. The common case.
        case echoedCommand
        /// The reply names nothing; this top-level key identifies it. Both
        /// motor-mode commands answer under `motor_mode`, so they serialise
        /// against each other — which is correct, since nothing tells them apart.
        case replyKey(String)
    }

    public enum Failure: Error, Equatable, Sendable {
        /// The robot answered, and said no. The text is its own.
        case robot(String)
        /// Nothing came back in time. Nothing on this channel promises a deadline,
        /// so one is imposed here — a caller left awaiting forever is worse off
        /// than one told the robot went quiet.
        case timedOut
        case closed
    }

    private let channel: any RemoteDataChannel
    private let timeout: Duration
    /// The robot is the one that opens the channel, and only once a negotiation
    /// this side does not drive has got far enough — so a command issued before
    /// that pays for the relay round trip, ICE and DTLS too. On the same budget as
    /// a reply, a slow network reads as a robot that never answered.
    private let openingTimeout: Duration
    private var reader: Task<Void, Never>?
    /// One waiter per correlation token, which is all the wire can distinguish.
    private var waiting: [String: CheckedContinuation<Data, any Error>] = [:]
    /// Commands already in flight under the same token. Awaited in turn.
    private var queued: [String: [CheckedContinuation<Void, Never>]] = [:]

    public init(
        channel: any RemoteDataChannel,
        timeout: Duration = .seconds(10),
        openingTimeout: Duration = .seconds(30)
    ) {
        self.channel = channel
        self.timeout = timeout
        self.openingTimeout = openingTimeout
    }

    /// Which budget a command gets. Two different waits are being bounded here —
    /// "the channel is not open yet" and "the robot has not answered" — and only
    /// the second one says anything about the robot. Asked afresh each time rather
    /// than latched, because the opening wait comes back: an ICE failure replaces
    /// the peer under a session that has been up for hours, and the command after
    /// it sits out a whole negotiation again.
    private var currentTimeout: Duration {
        channel.isOpen ? timeout : openingTimeout
    }

    deinit { reader?.cancel() }

    /// Sends a command and waits for the robot's answer.
    @discardableResult
    public func perform(
        _ command: String,
        payload: [String: RemoteValue] = [:],
        correlation: Correlation = .echoedCommand
    ) async throws -> Data {
        startReading()
        let token = switch correlation {
        case .echoedCommand: command
        case let .replyKey(key): key
        }
        await takeTurn(for: token)
        defer { yieldTurn(for: token) }

        var body = payload
        body["type"] = .string(command)
        let encoded = try JSONEncoder().encode(body)
        guard let text = String(bytes: encoded, encoding: .utf8) else {
            throw EncodingError.invalidValue(body, .init(
                codingPath: [],
                debugDescription: "command payload is not UTF-8"
            ))
        }

        // A timer that fails the waiter, rather than a task group racing the
        // waiter against a sleep. The group would have to await both children
        // before it could exit, and a continuation nothing resumes has no way to
        // let it — one continuation with exactly four ways to be resumed (reply,
        // send failure, deadline, closed channel) has no such corner.
        let deadline = Task { [budget = currentTimeout] in
            try? await Task.sleep(for: budget)
            guard !Task.isCancelled else { return }
            self.expire(token)
        }
        defer { deadline.cancel() }

        let reply = try await awaitReply(to: token, sending: text)
        try Self.throwIfError(in: reply)
        return reply
    }

    private func expire(_ token: String) {
        waiting.removeValue(forKey: token)?.resume(throwing: Failure.timedOut)
    }

    /// The same, with the answer decoded.
    @discardableResult
    public func perform<Reply: Decodable>(
        _ command: String,
        payload: [String: RemoteValue] = [:],
        correlation: Correlation = .echoedCommand,
        expecting _: Reply.Type
    ) async throws -> Reply {
        try await JSONDecoder().decode(
            Reply.self,
            from: perform(command, payload: payload, correlation: correlation)
        )
    }

    private func awaitReply(to token: String, sending text: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            waiting[token] = continuation
            Task { [channel] in
                do {
                    try await channel.send(text)
                } catch {
                    self.resume(token, with: .failure(error))
                }
            }
        }
    }

    private func startReading() {
        guard reader == nil else { return }
        reader = Task { [channel] in
            for await text in channel.messages() {
                guard !Task.isCancelled else { return }
                deliver(text)
            }
            endReading()
        }
    }

    /// A finished stream cannot be restarted, so surviving one means asking the
    /// channel for another — which the next command does, once the reader is
    /// cleared out of its way. Without this the first close is permanent: replies
    /// keep arriving at a channel nobody reads, and every later command sits out
    /// its whole deadline.
    private func endReading() {
        reader = nil
        failAll(with: .closed)
    }

    /// The robot also broadcasts messages nobody asked for — joint positions at
    /// 50 Hz, move progress, update log lines — so a message has to be routed
    /// before it can be delivered, and most of them are dropped here.
    private func deliver(_ text: String) {
        let data = Data(text.utf8)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        // Every unsolicited broadcast names a `type` and no reply ever does, which
        // is the only thing separating `{"state": …}`, an answer, from
        // `{"type": "daemon_status", …, "state": …}`, which is not.
        guard envelope.type == nil else { return }
        if let command = envelope.command {
            resume(command, with: .success(data))
        } else if let token = waiting.keys.first(where: envelope.keys.contains) {
            resume(token, with: .success(data))
        }
    }

    private func resume(_ token: String, with result: Result<Data, any Error>) {
        guard let continuation = waiting.removeValue(forKey: token) else { return }
        continuation.resume(with: result)
    }

    private func failAll(with failure: Failure) {
        let pending = waiting.values
        waiting = [:]
        for continuation in pending {
            continuation.resume(throwing: failure)
        }
    }

    // MARK: One command of a name at a time

    private func takeTurn(for command: String) async {
        guard waiting[command] != nil || queued[command] != nil else {
            queued[command] = []
            return
        }
        await withCheckedContinuation { continuation in
            queued[command, default: []].append(continuation)
        }
    }

    private func yieldTurn(for command: String) {
        guard var line = queued[command], !line.isEmpty else {
            queued[command] = nil
            return
        }
        let next = line.removeFirst()
        queued[command] = line
        next.resume()
    }

    /// Just enough of a message to route it, without modelling every shape the
    /// daemon can send.
    private struct Envelope: Decodable {
        let type: String?
        let command: String?
        let keys: Set<String>

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: AnyKey.self)
            keys = Set(container.allKeys.map(\.stringValue))
            type = try? container.decodeIfPresent(String.self, forKey: AnyKey("type"))
            command = try? container.decodeIfPresent(String.self, forKey: AnyKey("command"))
        }

        private struct AnyKey: CodingKey {
            let stringValue: String
            var intValue: Int? {
                nil
            }

            init(_ value: String) {
                stringValue = value
            }

            init?(stringValue: String) {
                self.init(stringValue)
            }

            init?(intValue _: Int) {
                nil
            }
        }
    }

    private static func throwIfError(in data: Data) throws {
        struct Reply: Decodable {
            let error: String?
        }
        if let error = try? JSONDecoder().decode(Reply.self, from: data).error, !error.isEmpty {
            throw Failure.robot(error)
        }
    }
}
