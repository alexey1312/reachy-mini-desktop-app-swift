import Foundation
import simd

/// Dimensions of the head's 6-RSS Stewart platform, read out of the robot's own
/// description.
///
/// Every value here also exists as a literal in upstream's kinematics data, but
/// deriving them keeps the client honest: a robot whose geometry differs — a new
/// hardware revision, a different shell — is drawn from its own numbers rather
/// than from ours. `StewartGeometryTests` pins the derivation against the known
/// dimensions so a change in either would be caught.
public struct StewartGeometry: Sendable {
    /// Six motor frames in the base link's frame, each already carrying the crank's
    /// vertical rise so the arm is a plain `[armLength, 0, 0]` in motor space.
    public let motorFrames: [simd_double4x4]
    /// Where each rod meets the platform, in the frame the daemon's head pose uses.
    public let branchPositions: [SIMD3<Double>]
    /// `rpy` of every `passive_i_x` joint: the rest orientation of each spherical
    /// wrist, seven in all.
    public let passiveOffsets: [SIMD3<Double>]
    /// Direction each rod points in its own wrist frame. Not axis-aligned for
    /// every leg — leg 2's mount is rotated.
    public let rodDirections: [SIMD3<Double>]
    public let armLength: Double
    /// The head pose is measured from the head's rest height, so this is added
    /// before solving.
    public let headHeightOffset: Double
    /// Rest transform from the pose's frame to the link the meshes hang off.
    public let headToDrawnLink: simd_double4x4

    public static let legCount = 6
    public static let passiveChainCount = 7

    public init?(urdf: URDFDocument) {
        var motorFrames: [simd_double4x4] = []
        var rodDirections: [SIMD3<Double>] = []
        var branchPositions: [SIMD3<Double>] = []
        var passiveOffsets: [SIMD3<Double>] = []
        var armLength: Double?

        for leg in 1 ... Self.legCount {
            guard let motor = urdf.joint(named: "stewart_\(leg)"),
                  let wrist = urdf.joint(named: "passive_\(leg)_x"),
                  let horn = urdf.restTransformFromRoot(motor.child),
                  let rod = Self.rodDirection(urdf: urdf, leg: leg),
                  let branch = Self.branchPosition(urdf: urdf, leg: leg) else { return nil }

            let crankRise = RigidTransform.transform(
                translation: SIMD3(0, 0, wrist.origin.xyz.z),
                rpy: .zero
            )
            motorFrames.append(horn * crankRise)
            rodDirections.append(rod)
            branchPositions.append(branch)
            armLength = armLength ?? simd_length(SIMD2(wrist.origin.xyz.x, wrist.origin.xyz.y))
        }

        for chain in 1 ... Self.passiveChainCount {
            guard let joint = urdf.joint(named: "passive_\(chain)_x") else { return nil }
            passiveOffsets.append(joint.origin.rpy)
        }

        guard let armLength,
              let head = urdf.restTransformFromRoot("head"),
              let headToDrawnLink = urdf.restTransform(from: "head", to: "xl_330") else { return nil }

        self.motorFrames = motorFrames
        self.branchPositions = branchPositions
        self.passiveOffsets = passiveOffsets
        self.rodDirections = rodDirections
        self.armLength = armLength
        headHeightOffset = head.translation.z
        self.headToDrawnLink = headToDrawnLink
    }

    /// Legs 1-5 end at a `closing_i_1` frame that closes the loop; leg 6 runs on
    /// through the seventh wrist to the head, so its rod is measured from there.
    private static func rodDirection(urdf: URDFDocument, leg: Int) -> SIMD3<Double>? {
        let joint = leg < legCount
            ? urdf.joints.first { $0.child == "closing_\(leg)_1" }
            : urdf.joint(named: "passive_\(passiveChainCount)_x")
        guard let offset = joint?.origin.xyz, simd_length(offset) > 0 else { return nil }
        return simd_normalize(offset)
    }

    /// Same asymmetry on the platform side: five closing frames, and the sixth
    /// point is the seventh wrist itself.
    private static func branchPosition(urdf: URDFDocument, leg: Int) -> SIMD3<Double>? {
        let target = leg < legCount ? "closing_\(leg)_2" : "passive_\(passiveChainCount)_link_x"
        return urdf.restTransform(from: "head", to: target)?.translation
    }
}
