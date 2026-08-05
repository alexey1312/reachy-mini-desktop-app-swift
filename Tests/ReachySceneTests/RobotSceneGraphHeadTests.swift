import Foundation
@testable import ReachyKit
@testable import ReachyScene
import RealityKit
import simd
import Testing

/// A synthetic 6-RSS description: enough structure for `StewartGeometry` to derive
/// itself, with the head parked at a rest height that is deliberately neither
/// upstream's 0.177 nor a real robot's 0.14957. Any lift taken from somewhere other
/// than this document then shows up as a displaced head.
private enum StewartFixture {
    static let headRestHeight = 0.15

    private static let crankCircle = 0.038
    private static let armLength = 0.04
    private static let crankRise = 0.01
    private static let rodRise = SIMD3<Double>(0, 0, 0.1)
    private static let headFrameOffset = SIMD3<Double>(0, 0, 0.02)
    private static let legAngles = [46.507, 73.493, 166.507, -166.507, -73.493, -46.507]
        .map { $0 * .pi / 180 }

    static func document() throws -> URDFDocument {
        var links = [
            URDFLink(name: "base", visuals: []),
            URDFLink(name: "xl_330", visuals: []),
            URDFLink(name: "head", visuals: []),
            URDFLink(name: "passive_7_link_x", visuals: []),
        ]
        var joints: [URDFJoint] = []

        for leg in 1 ... StewartGeometry.legCount {
            links.append(URDFLink(name: "horn_\(leg)", visuals: []))
            links.append(URDFLink(name: "passive_\(leg)_link_x", visuals: []))
            joints.append(URDFJoint(
                name: "stewart_\(leg)", kind: .revolute, parent: "base", child: "horn_\(leg)",
                origin: URDFPose(xyz: hornOrigin(leg), rpy: .zero), axis: SIMD3(0, 0, 1), limit: nil
            ))
            joints.append(fixed(
                "passive_\(leg)_x", from: "horn_\(leg)", to: "passive_\(leg)_link_x",
                xyz: SIMD3(armLength, 0, crankRise)
            ))
            guard leg < StewartGeometry.legCount else { continue }
            // Legs 1-5 close the loop through a pair of frames; leg 6 runs on to the head.
            links.append(URDFLink(name: "closing_\(leg)_1", visuals: []))
            links.append(URDFLink(name: "closing_\(leg)_2", visuals: []))
            joints.append(fixed("rod_\(leg)", from: "passive_\(leg)_link_x", to: "closing_\(leg)_1", xyz: rodRise))
            joints.append(fixed("close_\(leg)", from: "head", to: "closing_\(leg)_2", xyz: branchOrigin(leg)))
        }

        joints.append(fixed("passive_7_x", from: "passive_6_link_x", to: "passive_7_link_x", xyz: rodRise))
        joints.append(fixed("neck", from: "passive_7_link_x", to: "xl_330", xyz: neckOrigin))
        joints.append(fixed("head_frame", from: "xl_330", to: "head", xyz: headFrameOffset))

        return try URDFDocument(name: "fixture", links: links, joints: joints)
    }

    /// Whatever puts `head` at `headRestHeight` straight above the root, so the
    /// expected placement stays legible instead of being an accumulated sum.
    private static var neckOrigin: SIMD3<Double> {
        SIMD3(0, 0, headRestHeight) - headFrameOffset - rodRise
            - (hornOrigin(StewartGeometry.legCount) + SIMD3(armLength, 0, crankRise))
    }

    private static func hornOrigin(_ leg: Int) -> SIMD3<Double> {
        SIMD3(crankCircle * cos(legAngles[leg - 1]), crankCircle * sin(legAngles[leg - 1]), 0.02)
    }

    private static func branchOrigin(_ leg: Int) -> SIMD3<Double> {
        SIMD3(0.03 * cos(legAngles[leg - 1]), 0.03 * sin(legAngles[leg - 1]), 0)
    }

    private static func fixed(_ name: String, from: String, to: String, xyz: SIMD3<Double>) -> URDFJoint {
        URDFJoint(
            name: name, kind: .fixed, parent: from, child: to,
            origin: URDFPose(xyz: xyz, rpy: .zero), axis: SIMD3(1, 0, 0), limit: nil
        )
    }
}

@MainActor
@Suite("Robot scene graph head placement")
struct RobotSceneGraphHeadTests {
    /// The daemon's `fk` ends with `T_world_head.z -= head_z_offset`, so drawing the
    /// head is exactly that subtraction undone — whatever the description's own rest
    /// height happens to be. Deriving a lift from the URDF instead lands the head
    /// somewhere the daemon never reported, and away from the rods aimed at it.
    @Test("a head pose is placed by undoing the daemon's height offset")
    func poseUndoesTheDaemonOffset() throws {
        let urdf = try StewartFixture.document()
        let geometry = try #require(StewartGeometry(urdf: urdf))
        let graph = RobotSceneGraph(urdf: urdf, meshes: [:], geometry: geometry)
        let base = try #require(graph.entity(forLink: urdf.rootLinkName))
        let head = try #require(graph.entity(forLink: "head"))

        graph.applyHeadPose(matrix_identity_double4x4)
        let atOrigin = SIMD3<Double>(head.position(relativeTo: base))
        #expect(simd_distance(atOrigin, SIMD3(0, 0, geometry.headHeightOffset)) < 1e-5, "placed at \(atOrigin)")
        // The fixture's own rest height is deliberately not the offset, so a lift read
        // back out of the description would land here instead.
        #expect(abs(geometry.headHeightOffset - StewartFixture.headRestHeight) > 0.02)

        let reported = SIMD3<Double>(0.01, -0.02, 0.03)
        graph.applyHeadPose(RigidTransform.transform(translation: reported, rpy: .zero))
        let moved = SIMD3<Double>(head.position(relativeTo: base))
        #expect(simd_distance(moved, reported + SIMD3(0, 0, geometry.headHeightOffset)) < 1e-5, "placed at \(moved)")
    }

    /// The head is the one link driven straight from the pose, so without the
    /// platform's dimensions the graph has to leave it where the tree put it rather
    /// than guess a lift.
    @Test("without a Stewart platform the pose is ignored")
    func noGeometryLeavesTheTreeAlone() throws {
        let urdf = try URDFDocument(
            name: "stub",
            links: [URDFLink(name: "base", visuals: [])],
            joints: []
        )
        let graph = RobotSceneGraph(urdf: urdf, meshes: [:], geometry: nil)
        graph.applyHeadPose(matrix_identity_double4x4)
        #expect(graph.entity(forLink: "head") == nil)
    }
}
