import Foundation
@testable import ReachyKit
@testable import ReachyScene
import Testing

/// Serves a one-link robot and counts how often the description was fetched.
private final class SceneStubClient: RobotAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _urdfRequests = 0

    var urdfRequests: Int {
        lock.withLock { _urdfRequests }
    }

    func urdf() async throws -> String {
        lock.withLock { _urdfRequests += 1 }
        return """
        <robot name="stub">
          <link name="base">
            <visual><geometry><mesh filename="package://assets/base.stl"/></geometry></visual>
          </link>
        </robot>
        """
    }

    func stlAsset(named _: String) async throws -> Data {
        var data = Data(count: 80)
        withUnsafeBytes(of: UInt32(1).littleEndian) { data.append(contentsOf: $0) }
        let floats: [Float] = [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0]
        for value in floats {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [0, 0])
        return data
    }

    /// Unused by the geometry path, and without defaults in the protocol.
    func handshake() async throws -> RobotConnection.Handshake {
        throw URLError(.unsupportedURL)
    }

    func daemonStatus() async throws -> Components.Schemas.DaemonStatus {
        throw URLError(.unsupportedURL)
    }

    func wakeUp() async throws -> String {
        throw URLError(.unsupportedURL)
    }

    func gotoSleep() async throws -> String {
        throw URLError(.unsupportedURL)
    }
}

@MainActor
@Suite("Robot scene stream lifecycle")
struct RobotSceneModelStreamTests {
    private func makeModel(_ client: SceneStubClient) -> RobotSceneModel {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReachySceneStreamTests/\(UUID().uuidString)", isDirectory: true)
        return RobotSceneModel(
            address: .init(host: "127.0.0.1"),
            client: client,
            cache: GeometryCache(root: root)
        )
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("resuming before the scene exists does nothing")
    func resumeBeforeReady() {
        let model = makeModel(SceneStubClient())
        model.resumeStream()
        model.resumeStream()
        #expect(model.phase == .idle)
        model.stop()
    }

    @Test("pause and resume keep the geometry and the camera")
    func pauseKeepsGeometry() async {
        let client = SceneStubClient()
        let model = makeModel(client)
        let camera = model.camera

        model.start()
        await waitUntil(model.phase == .ready)
        #expect(model.phase == .ready)
        #expect(client.urdfRequests == 1)

        model.pauseStream()
        model.pauseStream()
        #expect(model.phase == .ready)

        model.resumeStream()
        #expect(model.phase == .ready)
        // The regression this API exists to prevent: `stop()`/`start()` would
        // re-fetch the description and re-frame the camera from scratch.
        #expect(client.urdfRequests == 1)
        #expect(model.camera === camera)
        model.stop()
    }
}
