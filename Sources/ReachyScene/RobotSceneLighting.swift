import RealityKit

/// Three-point lighting rig for the robot viewer.
///
/// A non-AR `RealityView` has no environment probe, so physically based materials
/// render black until something illuminates them. Directional lights are enough
/// here — the robot is a single small object viewed from outside.
@MainActor
public enum RobotSceneLighting {
    /// Key light carries the shading; fill opens the shadows; rim separates the
    /// silhouette from the background.
    public static func makeRig() -> Entity {
        let rig = Entity()
        rig.name = "lighting"
        rig.addChild(makeLight(named: "key", intensity: 2500, from: [0.6, 0.9, 0.8], castsShadow: true))
        rig.addChild(makeLight(named: "fill", intensity: 800, from: [-0.8, 0.2, 0.5], castsShadow: false))
        rig.addChild(makeLight(named: "rim", intensity: 600, from: [0, 0.4, -1.0], castsShadow: false))
        return rig
    }

    private static func makeLight(
        named name: String,
        intensity: Float,
        from position: SIMD3<Float>,
        castsShadow: Bool
    ) -> DirectionalLight {
        let light = DirectionalLight()
        light.name = name
        light.light.intensity = intensity
        // Three shadow casters muddy the image and cost fill rate for nothing, so
        // only the key light gets one. Reading `light.shadow` back is misleading:
        // it synthesises a default when the component is absent.
        if castsShadow {
            light.shadow = .init()
        }
        light.look(at: .zero, from: position, relativeTo: nil)
        return light
    }
}
