import Foundation
import ReachyKit

/// Starting and stopping one app, with no session around it.
///
/// `RobotSession` owns this for the app, where a failure belongs on a screen and
/// the store's own list is already loaded. A widget tap has neither: it has
/// seconds, one client, and a caller that has to be told what happened. So the
/// protocol lives here and both a Home Screen button and any future caller share
/// it, rather than the sequence existing twice and drifting — the same reason
/// `RobotPower` exists.
public struct RobotAppLauncher: Sendable {
    public enum Outcome: Equatable, Sendable {
        case started(name: String, title: String)
        case stopped(name: String)
    }

    /// The two ways a toggle refuses before the robot is even asked to do
    /// anything. Both are phrased as what the user can do, because a widget shows
    /// this sentence and nothing else.
    public enum Failure: Error, LocalizedError, Equatable {
        /// Another app holds the robot. `start-app` would evict it silently, and a
        /// widget is the wrong place to take that decision on someone's behalf.
        case busy(title: String)
        /// A `/` would split the `start-app` path into segments and 404. No Python
        /// entry point can contain one, so this turns an inexplicable failure into
        /// a legible one rather than guarding a real case.
        case unusableName(String)

        public var errorDescription: String? {
            switch self {
            case let .busy(title):
                "“\(title)” is running. Stop it first."
            case let .unusableName(name):
                "“\(name)” can't be started from here. Open Reachy Mini and start it there."
            }
        }
    }

    private let apps: any RobotAppsClient
    private let power: RobotPower
    private let isAwake: @Sendable () async throws -> Bool

    /// `assumeAwake` skips the readiness round trip when the caller already holds a
    /// reading worth trusting; nil asks the daemon.
    public init(
        client: any RobotAPIClient & RobotAppsClient,
        configuration: RobotSession.Configuration = .widgetIntent,
        assumeAwake: Bool?
    ) {
        apps = client
        power = RobotPower(client: client, configuration: configuration)
        isAwake = {
            if let assumeAwake {
                return assumeAwake
            }
            return try await client.daemonStatus().isAwake
        }
    }

    /// Test seam: the three things this needs, with no client to build them from.
    init(
        apps: any RobotAppsClient,
        power: RobotPower,
        isAwake: @escaping @Sendable () async throws -> Bool
    ) {
        self.apps = apps
        self.power = power
        self.isAwake = isAwake
    }

    /// Starts `name`, or stops it if it is what the robot is already running.
    public func toggle(name: String) async throws -> Outcome {
        guard !name.contains("/") else { throw Failure.unusableName(name) }

        // Asked first, not assumed from a snapshot: a reading can be half an hour
        // old, and this is the only thing standing between a tap and evicting
        // somebody else's app. The daemon has no way to refuse that for us —
        // `start-app/{app}/no-evict` is in the spec but 1.9.0 does not mount it.
        if let running = try await apps.currentAppStatus(), running.isBusy {
            guard running.app.name == name else {
                throw Failure.busy(title: running.app.title)
            }
            try await apps.stopCurrentApp()
            return .stopped(name: name)
        }

        // No check on the backend first: every `motors/*` route sits behind
        // `get_backend` and answers 503 at once when it is down, which reads as a
        // sentence. Starting the backend from here would be a ninety-second job in
        // a process that has seconds.
        if try await isAwake() == false {
            try await power.wake()
        }

        let started = try await apps.startApp(named: name)
        return .started(name: name, title: started.app.title)
    }
}

public extension RobotSession.Configuration {
    /// A widget intent runs on a budget the wake animation would eat whole.
    ///
    /// Safe to cut: `RobotPower.waitForMoveToFinish` returns normally when its
    /// deadline passes rather than throwing, so a shorter one means the app starts
    /// while the robot is still finishing its stretch — not that anything fails.
    static var widgetIntent: Self {
        var configuration = Self()
        configuration.moveCompletionTimeout = .seconds(4)
        return configuration
    }
}
