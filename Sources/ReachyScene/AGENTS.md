# ReachyScene

RealityKit rendering of the robot, driven by the state stream. Depends on ReachyKit. Read-only — nothing here
ever sends the robot a command.

- An `Entity` has one parent, so there must be **exactly one live `RealityView` per `RobotSceneModel`** — a second
  one silently steals the robot from the first. Move the view; never mount two (this rules out zoom transitions and
  `if/else` layout branches, both of which keep source and destination alive at once).
- Going off screen calls `pauseStream()`, not `stop()`: `stop()` clears `geometryTask` and `start()` guards on it
  being nil, so the pair re-downloads the URDF and re-frames the camera.
- **The camera entity is the one thing that must _not_ survive a `RealityView` teardown.** Everything else is
  deliberately reused across the 3D/camera switch — the meshes, the entity tree, the lighting, the angle. But
  "the camera we render from" is a role the _scene_ holds, not a property the entity carries: append the same
  `PerspectiveCamera` to the replacement scene and it is present without being active, so nothing at all is drawn.
  `OrbitCamera.makeEntity()` builds a new one per view and applies the stored angle to it; the controller then
  writes to that instance. The failure is silent and looks like an empty viewport with `phase == .ready`,
  `container.scene` non-nil and the full child count — no property of the entity graph reveals it, because the
  entity graph is fine. Reproducing it needs the real screen: a bare box in a two-branch `ViewBuilder` swap does
  _not_ show it, since a trivial view tree releases the old scene before the new one is made.
- `head_pose` is the head's transform with the daemon's `head_z_offset` subtracted — both engines end `fk` with
  `T_world_head.z -= head_z_offset` — so drawing it is that subtraction undone, and nothing else. The offset is a
  **literal 0.177**, not a robot dimension: the URDF's own rest height is 0.14957, 27 mm lower. `StewartGeometry`
  therefore carries 0.177 rather than deriving it, and `RobotSceneGraph` takes its lift from there so the head and
  the rods `PassiveJointSolver` aims at it cannot end up at two different heights. Either number alone looks
  plausible on screen — one detaches the head from the platform, the other sinks it into the body.
