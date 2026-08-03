import Foundation
import ReachyKit
import RealityKit
import simd

/// The robot as a RealityKit entity tree, with a fast path for re-posing it.
///
/// Built once from the URDF; after that only transforms change. Meshes and
/// materials are never rebuilt, which is what makes a 20 Hz update cheap.
@MainActor
public final class RobotSceneGraph {
    /// Carries the URDF's Z-up convention into RealityKit's Y-up world.
    public let root = Entity()

    private var linkEntities: [String: Entity] = [:]
    private var articulations: [Articulation] = []

    /// One movable joint, with its fixed frame pre-split so posing is a single
    /// quaternion multiply.
    private struct Articulation {
        let entity: Entity
        let jointName: String
        let originTranslation: SIMD3<Float>
        let originRotation: simd_quatf
        let axis: SIMD3<Float>
    }

    /// The link the daemon's `head_pose` describes, and the fixed offset from it
    /// to the link actually drawn.
    private let headLinkName = "xl_330"
    private var headToDrawnLink: simd_double4x4?
    private var baseEntity: Entity?

    /// `head_pose` is measured from the neutral head height, not from the base;
    /// the daemon adds this before solving and removes it after.
    private static let headHeightOffset = 0.177

    public init(urdf: URDFDocument, meshes: [String: MeshResource]) {
        root.name = "robot"
        root.transform = Transform(rotation: simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0)))
        let base = buildLink(named: urdf.rootLinkName, urdf: urdf, meshes: meshes)
        baseEntity = base
        root.addChild(base)
        // Derived from the URDF rather than hard-coded: `head_frame` fixes the
        // drawn link to the frame the pose refers to.
        headToDrawnLink = urdf.joints
            .first { $0.parent == headLinkName && $0.kind == .fixed && $0.child == "head" }
            .map(\.origin.matrix.inverse)
    }

    /// Places the head straight from the daemon's pose.
    ///
    /// The head hangs off leg 6 through both passive wrists, so until those are
    /// solved the tree alone puts it in the wrong place. Driving it directly keeps
    /// the model readable in the meantime.
    public func applyHeadPose(_ pose: simd_double4x4?) {
        guard let pose,
              let head = linkEntities[headLinkName],
              let base = baseEntity,
              let headToDrawnLink else { return }
        var lifted = pose
        lifted.columns.3.z += Self.headHeightOffset
        head.setTransformMatrix(simd_float4x4(lifted * headToDrawnLink), relativeTo: base)
    }

    public func entity(forLink name: String) -> Entity? {
        linkEntities[name]
    }

    /// What the camera should frame. Measured from the meshes rather than assumed,
    /// so it stays right whatever the robot's dimensions turn out to be.
    public var visualBounds: BoundingBox {
        root.visualBounds(relativeTo: nil)
    }

    public var movableJointNames: [String] {
        articulations.map(\.jointName)
    }

    /// Applies a pose. Joints the state does not mention keep their current angle,
    /// so a partial frame never snaps the robot to zero.
    public func apply(_ state: RobotJointState) {
        for articulation in articulations {
            guard let angle = state[articulation.jointName] else { continue }
            articulation.entity.transform = Transform(
                scale: .one,
                rotation: articulation.originRotation
                    * simd_quatf(angle: Float(angle), axis: articulation.axis),
                translation: articulation.originTranslation
            )
        }
    }

    private func buildLink(
        named name: String,
        urdf: URDFDocument,
        meshes: [String: MeshResource]
    ) -> Entity {
        let entity = Entity()
        entity.name = name
        linkEntities[name] = entity

        if let link = urdf.link(named: name) {
            for visual in link.visuals {
                if let model = makeVisual(visual, meshes: meshes) {
                    entity.addChild(model)
                }
            }
        }

        for joint in urdf.childJoints(of: name) {
            let child = buildLink(named: joint.child, urdf: urdf, meshes: meshes)
            attach(child, with: joint)
            entity.addChild(child)
        }
        return entity
    }

    private func attach(_ child: Entity, with joint: URDFJoint) {
        let origin = Transform(matrix: simd_float4x4(joint.origin.matrix))
        child.transform = origin
        guard joint.kind.isMovable else { return }
        articulations.append(Articulation(
            entity: child,
            jointName: joint.name,
            originTranslation: origin.translation,
            originRotation: origin.rotation,
            axis: SIMD3<Float>(joint.axis)
        ))
    }

    private func makeVisual(
        _ visual: URDFVisual,
        meshes: [String: MeshResource]
    ) -> ModelEntity? {
        guard case let .mesh(filename, _) = visual.geometry,
              let mesh = meshes[filename] else { return nil }
        let color = visual.color ?? URDFColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        let material = SimpleMaterial(
            color: .init(
                red: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: CGFloat(color.alpha)
            ),
            roughness: 0.45,
            isMetallic: false
        )
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.transform = Transform(matrix: simd_float4x4(visual.origin.matrix))
        return model
    }
}

private extension simd_float4x4 {
    init(_ matrix: simd_double4x4) {
        self.init(
            SIMD4<Float>(matrix.columns.0),
            SIMD4<Float>(matrix.columns.1),
            SIMD4<Float>(matrix.columns.2),
            SIMD4<Float>(matrix.columns.3)
        )
    }
}
