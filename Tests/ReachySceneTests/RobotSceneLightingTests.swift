@testable import ReachyScene
import RealityKit
import Testing

@MainActor
@Suite("Robot scene lighting")
struct RobotSceneLightingTests {
    @Test("rig carries a key, fill and rim light")
    func rigComposition() {
        let rig = RobotSceneLighting.makeRig()
        #expect(rig.children.count == 3)
        #expect(rig.children.compactMap(\.name).sorted() == ["fill", "key", "rim"])
    }

    /// `light.shadow` synthesises a default when the component is absent, so it
    /// always reads non-nil — the component itself is the only honest signal.
    @Test("only the key light casts a shadow")
    func shadows() {
        let rig = RobotSceneLighting.makeRig()
        let shadowed = rig.children
            .compactMap { $0 as? DirectionalLight }
            .filter { $0.components.has(DirectionalLightComponent.Shadow.self) }
            .map(\.name)
        #expect(shadowed == ["key"])
    }
}
