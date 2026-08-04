import ReachyKit
@testable import ReachyUI
import Testing

@MainActor
@Suite("Viewport model")
struct ViewportModelTests {
    private let address = RobotAddress(host: "127.0.0.1")

    /// Attaching alone starts nothing — the viewport has to be on screen first.
    @Test("nothing runs until the viewport is active")
    func inactiveStartsNothing() {
        let model = ViewportModel()
        model.attach(to: address)
        #expect(model.sceneModel == nil)
        #expect(model.cameraSession == nil)
        model.detach()
    }

    @Test("re-attaching to the same address keeps the loaded scene")
    func attachIsIdempotent() throws {
        let model = ViewportModel()
        model.setActive(true)
        model.attach(to: address)
        let scene = try #require(model.sceneModel)

        model.attach(to: address)
        #expect(model.sceneModel === scene)

        model.attach(to: RobotAddress(host: "127.0.0.2"))
        #expect(model.sceneModel !== scene)
        model.detach()
    }

    @Test("switching to the camera keeps the scene in memory")
    func switchingKeepsScene() throws {
        let model = ViewportModel()
        model.setActive(true)
        model.attach(to: address)
        let scene = try #require(model.sceneModel)

        model.setContent(.camera)
        #expect(model.cameraSession != nil)
        // Paused, not discarded: coming back must not re-download the geometry.
        #expect(model.sceneModel === scene)

        model.setContent(.scene)
        #expect(model.sceneModel === scene)
        // The peer connection is the expensive thing, and it does not survive.
        #expect(model.cameraSession == nil)
        model.detach()
    }

    @Test("leaving the viewport drops the camera and keeps the scene")
    func suspendDropsCameraOnly() throws {
        let model = ViewportModel()
        model.setActive(true)
        model.attach(to: address)
        model.setContent(.camera)
        let scene = try #require(model.sceneModel)

        model.setActive(false)
        #expect(model.cameraSession == nil)
        #expect(model.sceneModel === scene)

        model.setActive(true)
        #expect(model.cameraSession != nil)
        #expect(model.sceneModel === scene)
        model.detach()
    }

    @Test("detach is idempotent and clears both engines")
    func detachIsIdempotent() {
        let model = ViewportModel()
        model.setActive(true)
        model.attach(to: address)
        model.detach()
        model.detach()
        #expect(model.sceneModel == nil)
        #expect(model.cameraSession == nil)
    }
}
