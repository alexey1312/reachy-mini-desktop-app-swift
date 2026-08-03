import ReachyKit
import RealityKit

enum MeshResourceFactory {
    /// `MeshResource.init(from:)` is `nonisolated` from iOS 18 / macOS 15 onwards,
    /// so the 41 meshes of a Reachy Mini are built off the main actor and the UI
    /// never stalls behind them.
    static func make(_ mesh: STLMesh, named name: String) async throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(mesh.positions)
        descriptor.normals = MeshBuffers.Normals(mesh.normals)
        descriptor.primitives = .triangles(mesh.indices)
        return try await MeshResource(from: [descriptor])
    }

    /// Builds every mesh once; the URDF references some of them from several
    /// links, and they are shared rather than duplicated.
    static func makeAll(_ meshes: [String: STLMesh]) async -> [String: MeshResource] {
        await withTaskGroup(of: (String, MeshResource)?.self) { group in
            for (name, mesh) in meshes {
                group.addTask {
                    guard let resource = try? await make(mesh, named: name) else { return nil }
                    return (name, resource)
                }
            }
            var built: [String: MeshResource] = [:]
            for await entry in group {
                if let entry {
                    built[entry.0] = entry.1
                }
            }
            return built
        }
    }
}
