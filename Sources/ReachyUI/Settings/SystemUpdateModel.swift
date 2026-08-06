import Foundation
import Observation
import ReachyDesign
import ReachyKit

/// Drives one robot software update: check, start, stream the log, wait out the
/// restart, confirm the new version.
@MainActor
@Observable
final class SystemUpdateModel {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        /// The robot itself has no route to PyPI. Nothing the app can fix.
        case robotOffline(current: String)
        case available(current: String, latest: String)
        case installing
        /// The log socket closed, which is what the daemon restarting looks like.
        case restarting
        case finished(version: String)
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Shared with `LogConsoleView`, so pip output gets the same filter, pause and
    /// export the daemon journal has.
    let log = LogConsoleModel()

    private let session: RobotSession
    /// The two steps that cannot be driven through a stubbed client: one needs a live
    /// WebSocket, the other waits out a real reboot. Injected by tests only.
    private let makeEvents: (String) throws -> AsyncStream<UpdateLogEvent>
    private let reconnect: () async -> String?

    init(
        session: RobotSession,
        events: ((String) throws -> AsyncStream<UpdateLogEvent>)? = nil,
        reconnect: (() async -> String?)? = nil
    ) {
        self.session = session
        makeEvents = events ?? { [session] jobID in try session.updateLog(jobID: jobID) }
        self.reconnect = reconnect ?? { [session] in await session.reconnectAfterUpdate() }
    }

    var isBusy: Bool {
        switch state {
        case .checking, .installing, .restarting: true
        default: false
        }
    }

    func check(preRelease: Bool) async {
        state = .checking
        do {
            state = switch try await session.availableUpdate(preRelease: preRelease) {
            case let .upToDate(current): .upToDate(current: current)
            case let .robotOffline(current): .robotOffline(current: current)
            case let .available(current, latest): .available(current: current, latest: latest)
            }
        } catch {
            state = .failed(describe(error))
        }
    }

    /// Runs to a terminal state. The daemon dies mid-stream by design, so the socket
    /// closing is treated as "installed, now rebooting" rather than as a failure.
    func install(preRelease: Bool) async {
        guard case let .available(current, _) = state else { return }
        state = .installing
        log.clear()

        let jobID: String
        do {
            jobID = try await session.startUpdate(preRelease: preRelease)
        } catch {
            state = .failed(describe(error))
            return
        }

        do {
            for await event in try makeEvents(jobID) {
                switch event {
                case let .line(line):
                    log.ingest(line)
                case let .status(status):
                    if status == .failed {
                        state = .failed(String(localized: .reachy("The robot reported that the update failed.")))
                        return
                    }
                case let .rejected(reason):
                    state = .failed(reason)
                    return
                case .closed:
                    break
                }
            }
        } catch {
            state = .failed(describe(error))
            return
        }

        state = .restarting
        await confirmRestart(from: current)
    }

    private func confirmRestart(from previous: String) async {
        guard let version = await reconnect() else {
            state =
                .failed(
                    String(
                        localized: .reachy(
                            "The robot did not come back after the update. Power-cycle it and try again."
                        )
                    )
                )
            return
        }
        guard version != previous else {
            state = .failed(
                String(localized: .reachy("The update finished but the robot still reports \(version). "))
                    + String(localized: .reachy("A new enough release may not be published yet."))
            )
            return
        }
        state = .finished(version: version)
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

#if DEBUG
    extension SystemUpdateModel {
        /// One update parked mid-flight. `events` and `reconnect` are stubbed out rather than
        /// left at their defaults: the real ones open a WebSocket and wait out a reboot.
        static func preview(
            state: State,
            session: RobotSession? = nil,
            log lines: [String] = []
        ) -> SystemUpdateModel {
            let model = SystemUpdateModel(
                session: session ?? .preview(),
                events: { _ in AsyncStream { $0.finish() } },
                reconnect: { nil }
            )
            model.state = state
            for line in lines {
                model.log.ingest(line)
            }
            return model
        }
    }
#endif
