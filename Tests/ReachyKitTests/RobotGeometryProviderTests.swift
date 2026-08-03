import Foundation
@testable import ReachyKit
import simd
import Testing

/// Serves a two-link robot and counts what was actually fetched.
private final class GeometryStubClient: RobotAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _urdfRequests = 0
    private var _meshRequests: [String] = []
    var urdfXML: String

    init(urdfXML: String) {
        self.urdfXML = urdfXML
    }

    var urdfRequests: Int {
        lock.withLock { _urdfRequests }
    }

    var meshRequests: [String] {
        lock.withLock { _meshRequests }
    }

    func urdf() async throws -> String {
        lock.withLock { _urdfRequests += 1 }
        return urdfXML
    }

    func stlAsset(named filename: String) async throws -> Data {
        lock.withLock { _meshRequests.append(filename) }
        return GeometryStubClient.triangle
    }

    /// Unused by the geometry path.
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

    static let triangle: Data = {
        var data = Data(count: 80)
        withUnsafeBytes(of: UInt32(1).littleEndian) { data.append(contentsOf: $0) }
        let floats: [Float] = [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0]
        for value in floats {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [0, 0])
        return data
    }()
}

@Suite("Robot geometry provider")
struct RobotGeometryProviderTests {
    private static func urdf(mesh: String) -> String {
        """
        <robot name="stub">
          <link name="base">
            <visual><geometry><mesh filename="package://assets/\(mesh)"/></geometry></visual>
            <collision><geometry><mesh filename="package://assets/base_collider.stl"/></geometry></collision>
          </link>
          <link name="head">
            <visual><geometry><mesh filename="package://assets/head.stl"/></geometry></visual>
          </link>
          <joint name="neck" type="revolute">
            <parent link="base"/><child link="head"/><axis xyz="0 0 1"/>
          </joint>
        </robot>
        """
    }

    private func makeCache() -> (GeometryCache, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("geometry-tests-\(UUID().uuidString)", isDirectory: true)
        return (GeometryCache(root: root), root)
    }

    private func load(
        _ provider: RobotGeometryProvider
    ) async throws -> (geometry: RobotGeometry?, progress: [GeometryLoadProgress]) {
        var progress: [GeometryLoadProgress] = []
        var geometry: RobotGeometry?
        for try await step in await provider.load() {
            progress.append(step)
            if case let .ready(loaded) = step {
                geometry = loaded
            }
        }
        return (geometry, progress)
    }

    @Test("a cold load fetches the description and every visual mesh")
    func coldLoad() async throws {
        let (cache, root) = makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = GeometryStubClient(urdfXML: Self.urdf(mesh: "base.stl"))

        let result = try await load(RobotGeometryProvider(client: client, cache: cache))
        let geometry = try #require(result.geometry)

        #expect(client.urdfRequests == 1)
        #expect(client.meshRequests.sorted() == ["base.stl", "head.stl"])
        #expect(geometry.meshes.count == 2)
        #expect(geometry.urdf.rootLinkName == "base")
        #expect(result.progress.first == .fetchingDescription)
    }

    /// Collision meshes are never referenced by a `<visual>`, so downloading them
    /// would be pure waste — this is the assertion that keeps that true.
    @Test("collision meshes are never downloaded")
    func skipsCollisionMeshes() async throws {
        let (cache, root) = makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = GeometryStubClient(urdfXML: Self.urdf(mesh: "base.stl"))

        _ = try await load(RobotGeometryProvider(client: client, cache: cache))
        #expect(!client.meshRequests.contains("base_collider.stl"))
    }

    @Test("a warm load reuses the cache and downloads nothing")
    func warmLoad() async throws {
        let (cache, root) = makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = GeometryStubClient(urdfXML: Self.urdf(mesh: "base.stl"))

        _ = try await load(RobotGeometryProvider(client: client, cache: cache))
        let meshesAfterCold = client.meshRequests.count

        _ = try await load(RobotGeometryProvider(client: client, cache: cache))
        // The URDF is re-read every time — it is the only way to notice the robot
        // changed — but the meshes it names are already on disk.
        #expect(client.urdfRequests == 2)
        #expect(client.meshRequests.count == meshesAfterCold)
    }

    @Test("changing the description invalidates the cached meshes")
    func digestChangeInvalidates() async throws {
        let (cache, root) = makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = GeometryStubClient(urdfXML: Self.urdf(mesh: "base.stl"))

        let first = try await load(RobotGeometryProvider(client: client, cache: cache))
        client.urdfXML = Self.urdf(mesh: "base_v2.stl")
        let second = try await load(RobotGeometryProvider(client: client, cache: cache))

        #expect(try #require(first.geometry).digest != #require(second.geometry).digest)
        #expect(client.meshRequests.contains("base_v2.stl"))
    }

    @Test("progress counts up to the number of meshes")
    func progressReporting() async throws {
        let (cache, root) = makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = GeometryStubClient(urdfXML: Self.urdf(mesh: "base.stl"))

        let result = try await load(RobotGeometryProvider(client: client, cache: cache))
        let downloads = result.progress.compactMap { step -> (Int, Int)? in
            if case let .downloadingMeshes(completed, total) = step {
                return (completed, total)
            }
            return nil
        }
        #expect(downloads.first?.0 == 0)
        let last = try #require(downloads.last)
        #expect(last == (2, 2))
    }

    /// The manifest is written last, so a half-finished entry is never mistaken
    /// for a usable one.
    @Test("an entry is only complete once the manifest lands")
    func manifestMarksCompletion() throws {
        let (cache, root) = makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let xml = Self.urdf(mesh: "base.stl")
        let digest = GeometryCache.digest(of: xml)

        #expect(!cache.isComplete(digest: digest))
        try cache.store(urdf: xml, digest: digest)
        #expect(!cache.isComplete(digest: digest))
        try cache.finalize(digest: digest, meshes: ["base.stl"])
        #expect(cache.isComplete(digest: digest))
    }
}
