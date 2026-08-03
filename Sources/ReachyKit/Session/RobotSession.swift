import Foundation
import Observation

/// Connection lifecycle for one robot: handshake, health polling, wake/sleep.
///
/// State machine (mirrors upstream `EXTERNAL_PROBE` semantics):
/// - handshake success → `.connected` immediately
/// - any probe failure while connected → `.unreachable` immediately, polling continues
/// - recovery from `.unreachable` requires N consecutive successful probes
///   (hysteresis; upstream uses 2) to avoid flapping on a lossy Wi-Fi link
@MainActor
@Observable
public final class RobotSession {
    public enum ConnectionPhase: Equatable, Sendable {
        case idle
        case connecting
        case connected(RobotIdentity)
        case unreachable(RobotIdentity)
    }

    public struct Configuration: Sendable {
        /// Upstream polls every 3 s (5 s over robot Wi-Fi).
        public var pollInterval: Duration = .seconds(3)
        /// Consecutive successful probes required to leave `.unreachable`.
        public var requiredConsecutiveSuccesses = 2

        public init() {}
    }

    public private(set) var phase: ConnectionPhase = .idle
    public private(set) var address: RobotAddress?
    public private(set) var lastStatus: Components.Schemas.DaemonStatus?
    public private(set) var lastError: String?

    private let configuration: Configuration
    private let makeClient: @Sendable (RobotAddress) throws -> any RobotAPIClient
    private var client: (any RobotAPIClient)?
    private var pollTask: Task<Void, Never>?

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

    public func connect(to address: RobotAddress) async {
        disconnect()
        self.address = address
        phase = .connecting
        lastError = nil
        do {
            let client = try makeClient(address)
            let handshake = try await client.handshake()
            self.client = client
            lastStatus = handshake.status
            phase = .connected(handshake.identity)
            KnownRobots.lastAddress = address
            startPolling(identity: handshake.identity)
        } catch {
            lastError = "\(error)"
            phase = .idle
        }
    }

    public func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        client = nil
        lastStatus = nil
        phase = .idle
    }

    public func wake() async {
        await run { try await $0.wakeUp() }
    }

    public func sleep() async {
        await run { try await $0.gotoSleep() }
    }

    private func run(_ operation: (any RobotAPIClient) async throws -> Void) async {
        guard let client else { return }
        lastError = nil
        do {
            try await operation(client)
        } catch {
            lastError = "\(error)"
        }
    }

    private func startPolling(identity: RobotIdentity) {
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
