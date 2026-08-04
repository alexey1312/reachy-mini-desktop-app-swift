import Foundation
import Network
import Observation
import OpenAPIRuntime

/// Connection lifecycle for one robot: handshake, health polling, wake/sleep and recorded moves.
@MainActor
@Observable
public final class RobotSession {
    public enum ConnectionPhase: Equatable, Sendable {
        case idle
        case connecting(ConnectionStep)
        case connected(RobotIdentity)
        case unreachable(RobotIdentity)
    }

    /// Where a connection attempt currently stands. Split out of `.connecting`
    /// so a failure names the step it happened on instead of collapsing into one
    /// opaque spinner.
    public enum ConnectionStep: Equatable, Sendable {
        case handshaking
        case checkingBackend(RobotIdentity)
        /// The handshake succeeded but the robot backend is down. Terminal until
        /// the user picks one of start / proceed / cancel — starting it here would
        /// move the robot without being asked.
        case backendUnavailable(RobotIdentity, daemonMessage: String?)
        /// Latched for explicit connects only; automatic attempts fall back to
        /// `.idle` so the candidate loop keeps sweeping.
        case failed(ConnectionStage, message: String)
    }

    /// The steps a connection walks through, in order — the stepper's row model.
    public enum ConnectionStage: Int, CaseIterable, Equatable, Sendable {
        case connect
        case backend
    }

    public enum StageOutcome: Equatable, Sendable {
        case pending, active, done, attention, failed
    }

    /// Wake and sleep are long enough — a cold backend start is budgeted at 90 s —
    /// that the UI has to show what the robot is doing meanwhile.
    public enum PowerTransition: Equatable, Sendable {
        case startingBackend
        case wakingUp
        case goingToSleep
    }

    public struct MovePlayback: Equatable, Sendable {
        public let dataset: String
        public let move: String
        public let uuid: String
    }

    public struct Configuration: Sendable {
        /// Upstream polls every 3 s (5 s over robot Wi-Fi).
        public var pollInterval: Duration = .seconds(3)
        /// Consecutive successful probes required to leave `.unreachable`.
        public var requiredConsecutiveSuccesses = 2
        /// Move task polling is intentionally cheaper than rendering/state streaming.
        public var movePollInterval: Duration = .milliseconds(500)
        /// Upstream waits this long for a wake/sleep animation before moving on.
        public var moveCompletionTimeout: Duration = .seconds(10)
        /// Backend startup budget — upstream's `STARTUP.TIMEOUT_NORMAL`.
        public var daemonStartTimeout: Duration = .seconds(90)
        /// Motors need a moment to hold their pose before the animation starts.
        public var motorSettleDelay: Duration = .milliseconds(300)
        /// Connect-time readiness budget. We never start a backend during connect,
        /// so a stopped one is reported at once — this only covers the window
        /// between `state == running` and `backend.ready`.
        public var readinessTimeout: Duration = .seconds(8)
        public var readinessPollInterval: Duration = .milliseconds(500)

        public init() {}
    }

    // `internal(set)` rather than `private(set)`: the connect and power protocols
    // live in sibling files, and a `private` setter is scoped to this one.
    public internal(set) var phase: ConnectionPhase = .idle
    public internal(set) var address: RobotAddress?
    public internal(set) var lastStatus: Components.Schemas.DaemonStatus?
    public internal(set) var lastError: String?
    public private(set) var compatibilityWarning: String?
    public private(set) var currentMove: MovePlayback?
    public private(set) var isStoppingMove = false
    public internal(set) var powerTransition: PowerTransition?
    /// Explicit Disconnect suppresses discovery-driven reconnect until the user connects again.
    public private(set) var automaticConnectionAllowed = true

    let configuration: Configuration
    var client: (any RobotAPIClient)?
    var connectionAttemptID = UUID()

    private let makeClient: @Sendable (RobotAddress) throws -> any RobotAPIClient
    private var pollTask: Task<Void, Never>?
    private var movePollTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var moveCache: [String: [String]] = [:]

    /// `ReachyKitError` carries actionable text; raw interpolation would print
    /// the bare case name instead.
    ///
    /// The generated client wraps transport failures in a `ClientError` whose
    /// description carries the whole operation context — around twenty lines of
    /// `NSError` internals that bury the one sentence worth reading. Unwrap to the
    /// root cause first, so a refused connection reads as "Could not connect to
    /// the server."
    static func describe(_ error: Error) -> String {
        let root = rootCause(of: error)
        return (root as? LocalizedError)?.errorDescription ?? root.localizedDescription
    }

    private static func rootCause(of error: Error) -> Error {
        if let clientError = error as? ClientError {
            return rootCause(of: clientError.underlyingError)
        }
        return error
    }

    /// Production session talking to a real daemon.
    public convenience init(configuration: Configuration = .init()) {
        self.init(configuration: configuration) { try RobotConnection(address: $0) }
    }

    /// Injectable client factory for tests.
    public init(
        configuration: Configuration = .init(),
        makeClient: @escaping @Sendable (RobotAddress) throws -> any RobotAPIClient
    ) {
        self.configuration = configuration
        self.makeClient = makeClient
    }

    /// Connects manually by default. Automatic attempts respect a preceding explicit Disconnect.
    @discardableResult
    public func connect(to address: RobotAddress, automatically: Bool = false) async -> Bool {
        guard !automatically || automaticConnectionAllowed else { return false }
        if !automatically {
            automaticConnectionAllowed = true
        }

        let attemptID = UUID()
        connectionAttemptID = attemptID
        resetConnectionState()
        self.address = address
        phase = .connecting(.handshaking)
        lastError = nil

        do {
            let client = try makeClient(address)
            let handshake = try await client.handshake()
            guard connectionAttemptID == attemptID, !Task.isCancelled else {
                if connectionAttemptID == attemptID {
                    resetConnectionState()
                }
                return false
            }
            // Claimed before the readiness stage so `startBackend()` has something
            // to talk to while the attempt sits on `.backendUnavailable`. Only the
            // stepper is mounted then, so the rest of the surface stays unreachable.
            self.client = client
            lastStatus = handshake.status
            compatibilityWarning = handshake.compatibility.warningMessage
            KnownRobots.lastAddress = address
            phase = .connecting(.checkingBackend(handshake.identity))
            return await settleReadiness(
                identity: handshake.identity,
                status: handshake.status,
                client: client,
                attemptID: attemptID,
                automatically: automatically
            )
        } catch {
            guard connectionAttemptID == attemptID else { return false }
            guard !Task.isCancelled else {
                resetConnectionState()
                return false
            }
            return failAttempt(.connect, error: error, address: address, automatically: automatically)
        }
    }

    public func disconnect() {
        automaticConnectionAllowed = false
        connectionAttemptID = UUID()
        resetConnectionState()
        lastError = nil
    }

    /// Returns a session-scoped cached dataset index. Actual move assets stay daemon-side.
    public func moves(in dataset: String, refresh: Bool = false) async throws -> [String] {
        if !refresh, let cached = moveCache[dataset] {
            return cached
        }
        let moves = try await withClient { try await $0.listMoves(dataset: dataset) }
        moveCache[dataset] = moves
        return moves
    }

    public func playMove(dataset: String, move: String) async throws {
        guard let client else { throw ReachyKitError.notConnected }
        if currentMove != nil {
            await stopMove()
        }
        lastError = nil
        do {
            let uuid = try await client.playMove(dataset: dataset, move: move)
            let playback = MovePlayback(dataset: dataset, move: move, uuid: uuid)
            currentMove = playback
            startMonitoring(playback, client: client)
        } catch {
            lastError = Self.describe(error)
            throw error
        }
    }

    /// Stops both daemon tasks: motion and the separately-owned sound player.
    public func stopMove() async {
        guard let client, let playback = currentMove, !isStoppingMove else { return }
        isStoppingMove = true
        movePollTask?.cancel()
        movePollTask = nil

        let errors = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            group.addTask {
                do {
                    try await client.stopMove(uuid: playback.uuid)
                    return nil
                } catch {
                    return "Move: \(error)"
                }
            }
            group.addTask {
                do {
                    try await client.stopSound()
                    return nil
                } catch {
                    return "Sound: \(error)"
                }
            }

            var errors: [String] = []
            for await error in group {
                if let error {
                    errors.append(error)
                }
            }
            return errors
        }

        if currentMove?.uuid == playback.uuid {
            currentMove = nil
        }
        isStoppingMove = false
        lastError = errors.isEmpty ? nil : errors.sorted().joined(separator: "\n")
    }

    func resetConnectionState() {
        pollTask?.cancel()
        pollTask = nil
        movePollTask?.cancel()
        movePollTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        client = nil
        address = nil
        lastStatus = nil
        compatibilityWarning = nil
        currentMove = nil
        isStoppingMove = false
        powerTransition = nil
        moveCache = [:]
        phase = .idle
    }

    /// Polls the daemon's authoritative running-task list so natural completion
    /// clears the UI. Two misses avoid racing task registration just after play.
    private func startMonitoring(_ playback: MovePlayback, client: any RobotAPIClient) {
        movePollTask?.cancel()
        movePollTask = Task { [configuration] in
            var consecutiveMisses = 0
            while !Task.isCancelled, currentMove?.uuid == playback.uuid {
                try? await Task.sleep(for: configuration.movePollInterval)
                guard !Task.isCancelled, currentMove?.uuid == playback.uuid else { return }
                do {
                    let running = try await client.runningMoveUUIDs()
                    guard !Task.isCancelled, currentMove?.uuid == playback.uuid else { return }
                    if running.contains(playback.uuid) {
                        consecutiveMisses = 0
                    } else {
                        consecutiveMisses += 1
                        if consecutiveMisses >= 2 {
                            try? await client.stopSound()
                            guard !Task.isCancelled, currentMove?.uuid == playback.uuid else { return }
                            currentMove = nil
                            movePollTask = nil
                            return
                        }
                    }
                } catch {
                    // A transient status failure must not claim that playback ended.
                }
            }
        }
    }

    /// Network changes shouldn't wait for the next poll tick: losing the path
    /// drops to `.unreachable` immediately; regaining it restarts polling now.
    func startPathMonitor(identity: RobotIdentity) {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.pathChanged(satisfied: satisfied, identity: identity)
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func pathChanged(satisfied: Bool, identity: RobotIdentity) {
        guard client != nil else { return }
        if !satisfied {
            if case .connected = phase {
                phase = .unreachable(identity)
            }
        } else if case .unreachable = phase {
            startPolling(identity: identity)
        }
    }

    func startPolling(identity: RobotIdentity) {
        pollTask?.cancel()
        pollTask = Task { [configuration] in
            var consecutiveSuccesses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: configuration.pollInterval)
                guard !Task.isCancelled, let client = self.client else { return }
                do {
                    let status = try await client.daemonStatus()
                    lastStatus = status
                    if case .unreachable = phase {
                        consecutiveSuccesses += 1
                        if consecutiveSuccesses >= configuration.requiredConsecutiveSuccesses {
                            phase = .connected(identity)
                        }
                    } else {
                        consecutiveSuccesses = 1
                    }
                } catch {
                    consecutiveSuccesses = 0
                    phase = .unreachable(identity)
                }
            }
        }
    }
}
