import Foundation

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
            try assertSupportedDaemon()
            let status = try await client.daemonStatus()
            lastStatus = status
            guard status.state == .running else {
                // `wake_up=true` has the daemon enable the motors and play the
                // animation itself once the backend is up.
                _ = await runBackendStart(wakeUp: true, client: client)
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
            try assertSupportedDaemon()
            let uuid = try await client.gotoSleep()
            await waitForMoveToFinish(uuid, client: client)
            try await client.setMotorMode(.disabled)
        } catch {
            lastError = Self.describe(error)
        }
    }
}

extension RobotSession {
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

    /// Starts the backend and waits it out. Deliberately does not claim
    /// `powerTransition` as a latch — the caller owns that and its `defer`,
    /// because `wake()` has already claimed it before its first suspension point.
    func runBackendStart(wakeUp: Bool, client: any RobotAPIClient) async -> Bool {
        powerTransition = .startingBackend
        do {
            try await client.startDaemon(wakeUp: wakeUp)
        } catch {
            lastError = Self.describe(error)
            return false
        }
        guard await waitForDaemonRunning(client: client) else {
            lastError = "Robot backend did not start within \(configuration.daemonStartTimeout)."
            return false
        }
        return true
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
