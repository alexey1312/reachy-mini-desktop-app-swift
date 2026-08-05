// `RealityView` lives in the RealityKit/SwiftUI cross-import overlay. Xcode wires
// that up automatically; SwiftPM does not, so the overlay module is named here.
import _RealityKit_SwiftUI
import RealityKit
import SwiftUI

/// Renders the robot and lets the user orbit and zoom around it.
public struct RobotSceneView: View {
    private let model: RobotSceneModel

    public init(model: RobotSceneModel) {
        self.model = model
    }

    public var body: some View {
        RealityView { content in
            // The robot, its lighting and the camera angle are all reused across a
            // teardown; only the camera entity is rebuilt, because the active-camera
            // role belongs to the scene rather than to the entity carrying it.
            content.entities.append(model.container)
            // The scene supplies its own camera, so RealityKit's built-in controls
            // are off — they frame the scene once, at a point where the robot has
            // not downloaded yet.
            content.entities.append(model.camera.makeEntity())
        } update: { _ in
            // Intentionally empty: poses are written to the entity tree directly,
            // so SwiftUI is not in the 20 Hz path.
        }
        .gesture(orbit)
        .simultaneousGesture(zoom)
    }

    private var orbit: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                model.camera.drag(translation: SIMD2(
                    Float(value.translation.width),
                    Float(value.translation.height)
                ))
            }
            .onEnded { _ in model.camera.endGesture() }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in model.camera.magnify(by: Float(value.magnification)) }
            .onEnded { _ in model.camera.endGesture() }
    }
}
