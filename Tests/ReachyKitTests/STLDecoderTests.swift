import Foundation
@testable import ReachyKit
import simd
import Testing

@Suite("STL decoding")
struct STLDecoderTests {
    /// Builds a binary STL by hand so the fixtures stay in the test and no robot
    /// geometry has to be committed.
    private static func binarySTL(
        header: String = "test",
        triangles: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])]
    ) -> Data {
        var data = Data(count: 80)
        data.replaceSubrange(0 ..< min(header.utf8.count, 80), with: Array(header.utf8))
        withUnsafeBytes(of: UInt32(triangles.count).littleEndian) { data.append(contentsOf: $0) }
        for triangle in triangles {
            for value in [triangle.normal] + triangle.corners {
                for component in [value.x, value.y, value.z] {
                    withUnsafeBytes(of: component.bitPattern.littleEndian) { data.append(contentsOf: $0) }
                }
            }
            data.append(contentsOf: [0, 0]) // attribute byte count
        }
        return data
    }

    private static let unitTriangle: (normal: SIMD3<Float>, corners: [SIMD3<Float>]) = (
        normal: SIMD3(0, 0, 1),
        corners: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)]
    )

    @Test("reads a binary triangle")
    func binaryTriangle() throws {
        let mesh = try STLDecoder.decode(Self.binarySTL(triangles: [Self.unitTriangle]))
        #expect(mesh.triangleCount == 1)
        #expect(mesh.positions == Self.unitTriangle.corners)
        #expect(mesh.normals == Array(repeating: SIMD3(0, 0, 1), count: 3))
        #expect(mesh.indices == [0, 1, 2])
    }

    /// Exporters routinely write "solid" into a binary header, so sniffing the
    /// prefix misidentifies the file. The length check is what actually decides.
    @Test("a binary file whose header starts with 'solid' is still binary")
    func binaryWithSolidHeader() throws {
        let mesh = try STLDecoder.decode(Self.binarySTL(header: "solid cad-export", triangles: [Self.unitTriangle]))
        #expect(mesh.triangleCount == 1)
    }

    @Test("reads an ASCII triangle")
    func asciiTriangle() throws {
        let text = """
        solid model
          facet normal 0 0 1
            outer loop
              vertex 0 0 0
              vertex 1 0 0
              vertex 0 1 0
            endloop
          endfacet
        endsolid model
        """
        let mesh = try STLDecoder.decode(Data(text.utf8))
        #expect(mesh.triangleCount == 1)
        #expect(mesh.positions.last == SIMD3(0, 1, 0))
    }

    @Test("a zero normal is recomputed from the winding")
    func zeroNormalRepaired() throws {
        let triangle = (normal: SIMD3<Float>.zero, corners: Self.unitTriangle.corners)
        let mesh = try STLDecoder.decode(Self.binarySTL(triangles: [triangle]))
        #expect(mesh.normals.allSatisfy { simd_length($0 - SIMD3(0, 0, 1)) < 1e-6 })
    }

    @Test("an unnormalised normal is normalised")
    func normalIsUnitLength() throws {
        let triangle = (normal: SIMD3<Float>(0, 0, 7), corners: Self.unitTriangle.corners)
        let mesh = try STLDecoder.decode(Self.binarySTL(triangles: [triangle]))
        #expect(mesh.normals.allSatisfy { abs(simd_length($0) - 1) < 1e-6 })
    }

    @Test("a zero-area facet is dropped rather than shaded")
    func degenerateDropped() throws {
        let flat = (
            normal: SIMD3<Float>.zero,
            corners: [SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, 1, 1)]
        )
        #expect(throws: STLDecodeError.empty) {
            try STLDecoder.decode(Self.binarySTL(triangles: [flat]))
        }
        let mesh = try STLDecoder.decode(Self.binarySTL(triangles: [flat, Self.unitTriangle]))
        #expect(mesh.triangleCount == 1)
    }

    @Test("a truncated binary file is reported, not read past the end")
    func truncated() {
        var data = Self.binarySTL(triangles: [Self.unitTriangle, Self.unitTriangle])
        data.removeLast(20)
        #expect(throws: STLDecodeError.self) {
            try STLDecoder.decode(data)
        }
    }

    @Test("a file too short for a header is rejected")
    func tooShort() {
        #expect(throws: STLDecodeError.tooShort) {
            try STLDecoder.decode(Data(count: 10))
        }
    }

    @Test("bounds cover every vertex")
    func bounds() throws {
        let mesh = try STLDecoder.decode(Self.binarySTL(triangles: [Self.unitTriangle]))
        let bounds = try #require(mesh.bounds)
        #expect(bounds.min == SIMD3(0, 0, 0))
        #expect(bounds.max == SIMD3(1, 1, 0))
    }

    /// Three vertices per triangle even when they coincide — welding them would
    /// average the facet normals and soften the printed edges.
    @Test("shared corners are not welded")
    func noVertexWelding() throws {
        let second = (
            normal: SIMD3<Float>(0, 1, 0),
            corners: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)]
        )
        let mesh = try STLDecoder.decode(Self.binarySTL(triangles: [Self.unitTriangle, second]))
        #expect(mesh.positions.count == 6)
        #expect(mesh.indices == [0, 1, 2, 3, 4, 5])
    }
}
