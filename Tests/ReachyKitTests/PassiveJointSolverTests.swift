import Foundation
@testable import ReachyKit
import simd
import Testing

/// Needs a real robot description: the platform's dimensions come from the URDF,
/// and a toy fixture would only test the plumbing. Point `REACHY_URDF_FIXTURE` at
/// a file pulled from a daemon (`GET /api/kinematics/urdf`).
@Suite(
    "Stewart geometry and passive joints",
    .enabled(if: ProcessInfo.processInfo.environment["REACHY_URDF_FIXTURE"] != nil)
)
struct PassiveJointSolverTests {
    private func loadGeometry() throws -> StewartGeometry {
        let path = try #require(ProcessInfo.processInfo.environment["REACHY_URDF_FIXTURE"])
        let urdf = try URDFParser.parse(Data(contentsOf: URL(fileURLWithPath: path)))
        return try #require(StewartGeometry(urdf: urdf))
    }

    private func polar(_ point: SIMD3<Double>) -> (radius: Double, degrees: Double) {
        (sqrt(point.x * point.x + point.y * point.y), atan2(point.y, point.x) * 180 / .pi)
    }

    // MARK: - Geometry

    /// Pins the derivation against the dimensions upstream keeps as literals. If
    /// these drift, either the robot changed or the derivation broke — and the
    /// difference matters.
    @Test("motor frames land on a 38 mm circle at the measured height")
    func motorFrames() throws {
        let geometry = try loadGeometry()
        let expected = [44.742, 75.258, 164.742, -164.743, -75.258, -44.743]
        for (index, frame) in geometry.motorFrames.enumerated() {
            let (radius, degrees) = polar(frame.translation)
            #expect(abs(radius - 0.038) < 1e-5, "leg \(index + 1) radius \(radius)")
            #expect(abs(frame.translation.z - 0.0766334) < 1e-6)
            #expect(abs(degrees - expected[index]) < 1e-2, "leg \(index + 1) angle \(degrees)")
        }
    }

    @Test("rod mounts sit on a 30 mm circle in the head's plane")
    func branchPositions() throws {
        let geometry = try loadGeometry()
        let expected = [46.507, 73.493, 166.507, -166.507, -73.493, -46.507]
        for (index, point) in geometry.branchPositions.enumerated() {
            let (radius, degrees) = polar(point)
            #expect(abs(radius - 0.030) < 1e-5, "leg \(index + 1) radius \(radius)")
            #expect(abs(point.z) < 1e-6)
            #expect(abs(degrees - expected[index]) < 1e-2, "leg \(index + 1) angle \(degrees)")
        }
    }

    /// Upstream carries 0.177 for the head height. That number is expressed in
    /// their solver's own frame, not the URDF root, and using it here would put
    /// the rest pose 27 mm out — `restPose` below is what pins the right value.
    @Test("crank and head height come out of the description")
    func scalars() throws {
        let geometry = try loadGeometry()
        #expect(abs(geometry.armLength - 0.04) < 1e-9)
        #expect(abs(geometry.headHeightOffset - 0.14957) < 1e-4)
    }

    /// Leg 2's rod mount is rotated, so its direction is not axis-aligned like the
    /// others. Deriving it from the URDF picks that up for free.
    @Test("rod directions include leg 2's rotated mount")
    func rodDirections() throws {
        let geometry = try loadGeometry()
        #expect(simd_distance(geometry.rodDirections[0], SIMD3(1, 0, 0)) < 1e-6)
        #expect(simd_distance(geometry.rodDirections[2], SIMD3(-1, 0, 0)) < 1e-6)
        // The URDF writes that mount with five significant figures, so it lands a
        // fraction of a milliradian off upstream's stored constant.
        let leg2 = geometry.rodDirections[1]
        #expect(simd_distance(leg2, SIMD3(0.50606941, -0.85796418, -0.08826792)) < 1e-3)
    }

    @Test("seven wrist orientations are read, one per spherical joint")
    func passiveOffsets() throws {
        let geometry = try loadGeometry()
        #expect(geometry.passiveOffsets.count == 7)
        #expect(simd_distance(geometry.passiveOffsets[0], SIMD3(-0.13754, -0.0882156, 2.10349)) < 1e-5)
    }

    // MARK: - Solver

    /// The URDF's zero configuration is a real assembled pose, so a robot sitting
    /// at rest must solve to all-zero wrists. Any frame taken from the wrong
    /// parent shows up here immediately.
    @Test("a robot at rest solves to zero everywhere")
    func restPose() throws {
        let solver = try PassiveJointSolver(geometry: loadGeometry())
        let angles = solver.solve(
            headPose: matrix_identity_double4x4,
            bodyYaw: 0,
            stewart: Array(repeating: 0, count: 6)
        )
        #expect(angles.count == 21)
        // The six legs come out exactly zero; the seventh wrist carries about a
        // hundredth of a milliradian from the six-figure `rpy` in the description.
        for (index, angle) in angles.enumerated() {
            #expect(abs(angle) < 1e-4, "joint \(index) is \(angle)")
        }
        for (index, angle) in angles.prefix(18).enumerated() {
            #expect(abs(angle) < 1e-9, "leg joint \(index) is \(angle)")
        }
    }

    /// The angles are only useful if they rebuild the rotation they were extracted
    /// from — this is where an Euler convention mismatch would surface, and it
    /// holds for any input rather than just the rest pose.
    @Test("the reported angles rebuild each rod's direction")
    func anglesReproduceRodDirections() throws {
        let geometry = try loadGeometry()
        let solver = PassiveJointSolver(geometry: geometry)
        let stewart = [0.22, -0.18, 0.31, -0.27, 0.14, -0.35]
        let bodyYaw = 0.4
        var pose = RigidTransform.transform(
            translation: SIMD3(0.006, -0.004, 0.012),
            rpy: SIMD3(0.18, -0.22, 0.1)
        )
        let angles = solver.solve(headPose: pose, bodyYaw: bodyYaw, stewart: stewart)

        // Rebuild the solver's own frame so the comparison is like for like.
        pose.columns.3.z += geometry.headHeightOffset
        pose = RigidTransform.transform(
            rotation: RigidTransform.rotation(rpy: SIMD3(0, 0, -bodyYaw)),
            translation: .zero
        ) * pose

        for leg in 0 ..< 6 {
            let motor = geometry.motorFrames[leg]
            let crank = RigidTransform.rotation(rpy: SIMD3(0, 0, stewart[leg]))
            let mount = pose.rotation * geometry.branchPositions[leg] + pose.translation
            let tip = (motor * SIMD4(crank * SIMD3(geometry.armLength, 0, 0), 1)).xyz
            let wrist = motor.rotation * crank
                * RigidTransform.rotation(rpy: geometry.passiveOffsets[leg])

            let solved = SIMD3(angles[leg * 3], angles[leg * 3 + 1], angles[leg * 3 + 2])
            let pointing = wrist * RigidTransform.rotation(rpy: solved) * geometry.rodDirections[leg]
            #expect(simd_distance(pointing, simd_normalize(mount - tip)) < 1e-9, "leg \(leg + 1)")
        }
    }

    /// Step two of the algorithm removes the body's rotation, so turning the whole
    /// robot must leave the linkage untouched.
    @Test("turning the body does not move the linkage")
    func bodyYawInvariance() throws {
        let solver = try PassiveJointSolver(geometry: loadGeometry())
        let stewart = [0.12, -0.08, 0.05, -0.11, 0.09, -0.03]
        let pose = RigidTransform.transform(
            translation: SIMD3(0.004, -0.002, 0.006),
            rpy: SIMD3(0.05, -0.03, 0.02)
        )
        let straight = solver.solve(headPose: pose, bodyYaw: 0, stewart: stewart)

        let yaw = 0.7
        let turned = RigidTransform.transform(
            rotation: RigidTransform.rotation(rpy: SIMD3(0, 0, yaw)),
            translation: .zero
        ) * pose
        let rotated = solver.solve(headPose: turned, bodyYaw: yaw, stewart: stewart)

        for index in 0 ..< 21 {
            #expect(abs(straight[index] - rotated[index]) < 1e-9, "joint \(index)")
        }
    }

    @Test("a moved head produces finite angles for every wrist")
    func movedHead() throws {
        let solver = try PassiveJointSolver(geometry: loadGeometry())
        let pose = RigidTransform.transform(
            translation: SIMD3(0.005, 0.003, 0.01),
            rpy: SIMD3(0.2, -0.15, 0.3)
        )
        let angles = solver.solve(
            headPose: pose,
            bodyYaw: 0.2,
            stewart: [0.3, -0.25, 0.18, -0.32, 0.27, -0.2]
        )
        let allFinite = angles.allSatisfy(\.isFinite)
        let largest = angles.map(abs).max() ?? 0
        #expect(angles.count == 21)
        #expect(allFinite)
        #expect(largest > 1e-3, "a displaced head should bend the wrists")
    }

    @Test("a short motor vector is refused rather than producing nonsense")
    func guardsAgainstShortInput() throws {
        let solver = try PassiveJointSolver(geometry: loadGeometry())
        let angles = solver.solve(headPose: matrix_identity_double4x4, bodyYaw: 0, stewart: [0, 0])
        #expect(angles == Array(repeating: 0, count: 21))
    }
}
