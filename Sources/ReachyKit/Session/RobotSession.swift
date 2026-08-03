import Foundation
import Network
import Observation

/// Connection lifecycle for one robot: handshake, health polling, wake/sleep and recorded moves.
@MainActor
@Observable
public final class RobotSession {
    public enum ConnectionPhase: Equatable, Sendable {
        case idle
        case connecting
        case connected(RobotIdentity)
        case unreachable(RobotIdentity)
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

        public init() {}
    }

    public private(set) var phase: ConnectionPhase = .idle
    public private(set) var address: RobotAddress?
    public private(set) var lastStatus: Components.Schemas.DaemonStatus?
    public private(set) var lastError: String?
    public private(set) var compatibilityWarning: String?
    public private(set) var currentMove: MovePlayback?
    public private(set) var isStoppingMove = false
    public private(set) var powerTransition: PowerTransition?
    /// Explicit Disconnect suppresses discovery-driven reconnect until the user connects again.
    public private(set) var automaticConnectionAllowed = true

    private let configuration: Configuration
    private let makeClient: @Sendable (RobotAddress) throws -> any RobotAPIClient
    private var client: (any RobotAPIClient)?
    private var pollTask: Task<Void, Never>?
    private var movePollTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var moveCache: [String: [String]] = [:]
    private var connectionAttemptID = UUID()

    /// `ReachyKitError` carries actionable text; raw interpolation would print
    /// the bare case name instead.
    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
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
        phase = .connecting
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
            self.client = client
            lastStatus = handshake.status
            compatibilityWarning = handshake.compatibility.warningMessage
            phase = .connected(handshake.identity)
            KnownRobots.lastAddress = address
            startPolling(identity: handshake.identity)
            startPathMonitor(identity: handshake.identity)
            return true
        } catch {
            guard connectionAttemptID == attemptID else { return false }
            resetConnectionState()
            if !Task.isCancelled {
                lastError = Self.describe(error)
            }
            return false
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
        guard let client else { throw ReachyKitError.notConnected }
        do {
            let moves = try await client.listMoves(dataset: dataset)
            moveCache[dataset] = moves
            lastError = nil
            return moves
        } catch {
            lastError = Self.describe(error)
            throw error
        }
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

    private func resetConnectionState() {
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
    private func startPathMonitor(identity: RobotIdentity) {
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

    private func startPolling(identity: RobotIdentity) {
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

// MARK: - Wake / sleep

/// Both transitions are multi-step protocols against the daemon, not single
/// calls: `/move/play/wake_up` and `/move/play/goto_sleep` only play animations
/// and never touch the motor control mode, and they answer 503 while the robot
/// backend is down. Enabling and cutting motor power is the caller's job.
public extension RobotSession {
    /// The branch is picked from a freshly fetched status rather than `lastStatus`,
    /// which may be a poll interval out of date — long enough to send motor
    /// commands at a backend that is already gone.
    func wake() async {
        guard let client, powerTransition == nil else { return }
        lastError = nil
        // Claimed before the first suspension point: `@MainActor` re-enters on
        // every `await`, so a later latch would let a double tap through.
        powerTransition = .wakingUp
        defer { powerTransition = nil }
        do {
            let status = try await client.daemonStatus()
            lastStatus = status
            guard status.state == .running else {
                // `wake_up=true` has the daemon enable the motors and play the
                // animation itself once the backend is up.
                powerTransition = .startingBackend
                try await client.startDaemon(wakeUp: true)
                if await !waitForDaemonRunning(client: client) {
                    lastError = "Robot backend did not start within \(configuration.daemonStartTimeout)."
                }
                return
            }
            try await client.setMotorMode(.enabled)
            try await Task.sleep(for: configuration.motorSettleDelay)
            let uuid = try await client.wakeUp()
            await waitForMoveToFinish(uuid, client: client)
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// Mirror image of wake: the animation must finish *before* power is cut,
    /// otherwise the head drops wherever it happens to be.
    func sleep() async {
        guard let client, powerTransition == nil else { return }
        lastError = nil
        powerTransition = .goingToSleep
        defer { powerTransition = nil }
        do {
            let uuid = try await client.gotoSleep()
            await waitForMoveToFinish(uuid, client: client)
            try await client.setMotorMode(.disabled)
        } catch {
            lastError = Self.describe(error)
        }
    }
}

private extension RobotSession {
    /// Polls the daemon's authoritative running-move list until `uuid` is gone.
    /// A timeout returns normally: parking the motors matters more than proof
    /// that the animation ran to completion.
    func waitForMoveToFinish(_ uuid: String, client: any RobotAPIClient) async {
        let deadline = ContinuousClock.now + configuration.moveCompletionTimeout
        while ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: configuration.movePollInterval)
            guard let running = try? await client.runningMoveUUIDs() else { continue }
            if !running.contains(uuid) {
                return
            }
        }
    }

    /// Waits out the background start job, refreshing `lastStatus` as it goes.
    func waitForDaemonRunning(client: any RobotAPIClient) async -> Bool {
        let deadline = ContinuousClock.now + configuration.daemonStartTimeout
        while ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: configuration.pollInterval)
            guard let status = try? await client.daemonStatus() else { continue }
            lastStatus = status
            switch status.state {
            case .running: return true
            case .error, .stopped: return false
            default: continue
            }
        }
        return false
    }
}
