@testable import ReachyKit
import simd
import Testing

@Suite("Rigid transform maths")
struct RigidTransformTests {
    /// The daemon flattens poses row by row while simd stores columns. Sixteen
    /// distinct values are the only way to catch a transposition — a symmetric
    /// fixture would pass either way.
    @Test("row-major values land in the right cells")
    func rowMajorUnpacking() throws {
        let values = (1 ... 16).map(Double.init)
        let matrix = try #require(RigidTransform.matrix(rowMajor: values))
        for row in 0 ..< 4 {
            for column in 0 ..< 4 {
                #expect(matrix[column][row] == values[row * 4 + column])
            }
        }
    }

    @Test("rejects a wrong-sized pose")
    func rowMajorRejectsShortInput() {
        #expect(RigidTransform.matrix(rowMajor: Array(repeating: 0, count: 15)) == nil)
    }

    @Test(
        "euler extraction inverts euler construction",
        arguments: [
            SIMD3(0.0, 0.0, 0.0),
            SIMD3(0.3, -0.2, 1.1),
            SIMD3(-1.2, 0.7, -2.5),
            SIMD3(3.0, -1.4, 0.1),
            SIMD3(-0.13754, -0.0882156, 2.10349), // passive_1_x in the robot's URDF
        ]
    )
    func eulerRoundTrip(rpy: SIMD3<Double>) {
        let recovered = RigidTransform.euler(from: RigidTransform.rotation(rpy: rpy))
        // Compare rotations, not angles: different triplets can name one rotation.
        let original = RigidTransform.rotation(rpy: rpy)
        let rebuilt = RigidTransform.rotation(rpy: recovered)
        for column in 0 ..< 3 {
            for row in 0 ..< 3 {
                #expect(abs(original[column][row] - rebuilt[column][row]) < 1e-9)
            }
        }
    }

    @Test("gimbal lock still reproduces the rotation", arguments: [1.0, -1.0])
    func gimbalLock(sign: Double) {
        let rpy = SIMD3(0.4, sign * .pi / 2, 1.3)
        let original = RigidTransform.rotation(rpy: rpy)
        let rebuilt = RigidTransform.rotation(rpy: RigidTransform.euler(from: original))
        for column in 0 ..< 3 {
            for row in 0 ..< 3 {
                #expect(abs(original[column][row] - rebuilt[column][row]) < 1e-9)
            }
        }
    }

    @Test("transform keeps translation in the last column")
    func transformTranslation() {
        let matrix = RigidTransform.transform(
            translation: SIMD3(0.04, -0.5, 0.177),
            rpy: SIMD3(0.1, 0.2, 0.3)
        )
        #expect(abs(matrix.translation.x - 0.04) < 1e-12)
        #expect(abs(matrix.translation.y + 0.5) < 1e-12)
        #expect(abs(matrix.translation.z - 0.177) < 1e-12)
        #expect(matrix[3][3] == 1)
    }

    @Test("axis rotation matches the equivalent rpy")
    func axisRotation() {
        let byAxis = RigidTransform.rotation(axis: SIMD3(0, 0, 1), angle: 0.7)
        let byEuler = RigidTransform.rotation(rpy: SIMD3(0, 0, 0.7))
        for column in 0 ..< 3 {
            for row in 0 ..< 3 {
                #expect(abs(byAxis[column][row] - byEuler[column][row]) < 1e-12)
            }
        }
    }
}
