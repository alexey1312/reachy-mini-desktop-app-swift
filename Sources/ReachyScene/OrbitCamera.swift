import RealityKit
import simd

/// Camera that circles a fixed point, driven by gestures.
///
/// RealityKit's built-in orbit controls frame whatever the scene contains when
/// the view is first made. The robot arrives over the network seconds later, so
/// they end up framing nothing and park the camera inside the model — hence a
/// controller that can re-frame once the geometry is actually there.
@MainActor
public final class OrbitCamera {
    public let entity = PerspectiveCamera()

    /// Rotation around the vertical axis.
    private var azimuth: Float = .pi * 0.85
    /// Height above the horizon, clamped short of the poles where the up vector
    /// degenerates and the view flips.
    private var elevation: Float = 0.42
    private var distance: Float = 0.6
    private var target: SIMD3<Float> = .zero

    private var startAzimuth: Float?
    private var startElevation: Float?
    private var startDistance: Float?

    private var minimumDistance: Float = 0.05
    private var maximumDistance: Float = 5

    private static let maximumElevation: Float = .pi / 2 - 0.05
    /// Radians per point of drag — a full turn takes roughly a screen width.
    private static let dragSensitivity: Float = 0.01

    public init() {
        entity.name = "camera"
        apply()
    }

    private var framedBounds: BoundingBox?

    /// Restores the starting three-quarter view.
    public func reset() {
        azimuth = .pi * 0.85
        elevation = 0.42
        endGesture()
        if let framedBounds {
            frame(framedBounds)
        } else {
            apply()
        }
    }

    /// Points the camera at the model and backs off far enough to see all of it.
    public func frame(_ bounds: BoundingBox) {
        framedBounds = bounds
        target = bounds.center
        let radius = max(simd_length(bounds.extents) / 2, 0.01)
        // Vertical field of view is 60° by default; 2.2 radii leaves a margin so
        // the robot does not touch the edges of the screen.
        distance = radius * 2.2
        minimumDistance = radius * 0.6
        maximumDistance = radius * 12
        apply()
    }

    public func drag(translation: SIMD2<Float>) {
        let azimuthStart = startAzimuth ?? azimuth
        let elevationStart = startElevation ?? elevation
        startAzimuth = azimuthStart
        startElevation = elevationStart
        azimuth = azimuthStart - translation.x * Self.dragSensitivity
        elevation = (elevationStart + translation.y * Self.dragSensitivity)
            .clamped(to: -Self.maximumElevation ... Self.maximumElevation)
        apply()
    }

    public func magnify(by scale: Float) {
        let start = startDistance ?? distance
        startDistance = start
        distance = (start / max(scale, 0.01)).clamped(to: minimumDistance ... maximumDistance)
        apply()
    }

    /// Gestures report cumulative values, so the anchor is captured on the first
    /// change and released when the gesture ends.
    public func endGesture() {
        startAzimuth = nil
        startElevation = nil
        startDistance = nil
    }

    private func apply() {
        let horizontal = distance * cos(elevation)
        let position = target + SIMD3(
            horizontal * sin(azimuth),
            distance * sin(elevation),
            horizontal * cos(azimuth)
        )
        entity.look(at: target, from: position, relativeTo: nil)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
