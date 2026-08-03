import Foundation

/// Streams the robot's full state from `ws://<host>:<port>/api/state/ws/full` (20 Hz).
///
/// Reconnects forever with exponential backoff until the stream's consumer cancels.
/// The stream buffers `.bufferingNewest(1)`: a slow consumer always observes the
/// newest state, coalescing the 20 Hz feed to its own pace (render at display rate,
/// not packet rate — lesson from upstream).
public struct StateStreamClient: Sendable {
    public struct Configuration: Sendable {
        public var initialBackoff: Duration = .milliseconds(500)
        public var maxBackoff: Duration = .seconds(15)
        public init() {}
    }

    public static let statePath = "/api/state/ws/full"

    private let url: URL
    private let configuration: Configuration
    private let session: URLSession

    public init(
        address: RobotAddress,
        configuration: Configuration = .init(),
        session: URLSession = .shared
    ) throws {
        guard let url = address.webSocketURL(path: Self.statePath) else {
            throw ReachyKitError.invalidAddress(address)
        }
        self.url = url
        self.configuration = configuration
        self.session = session
    }

    /// Latest-wins stream of robot state. Never throws; ends only on cancellation.
    public func states() -> AsyncStream<Components.Schemas.FullState> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Components.Schemas.FullState.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let task = Task { [url, configuration, session] in
            let decoder = JSONDecoder.reachyDaemon
            var backoff = configuration.initialBackoff
            while !Task.isCancelled {
                let socket = session.webSocketTask(with: url)
                socket.resume()
                do {
                    while true {
                        let message = try await socket.receive()
                        let data: Data? = switch message {
                        case let .data(data): data
                        case let .string(text): Data(text.utf8)
                        @unknown default: nil
                        }
                        // ponytail: undecodable frames are dropped silently; surface a
                        // decode-error counter once there's UI to show it in
                        if let data, let state = try? decoder.decode(Components.Schemas.FullState.self, from: data) {
                            continuation.yield(state)
                            backoff = configuration.initialBackoff
                        }
                    }
                } catch {
                    socket.cancel(with: .goingAway, reason: nil)
                }
                if Task.isCancelled {
                    break
                }
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, configuration.maxBackoff)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
