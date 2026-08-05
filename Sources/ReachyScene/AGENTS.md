# ReachyScene

RealityKit rendering of the robot, driven by the state stream. Depends on ReachyKit. Read-only — nothing here
ever sends the robot a command.

- An `Entity` has one parent, so there must be **exactly one live `RealityView` per `RobotSceneModel`** — a second
  one silently steals the robot from the first. Move the view; never mount two (this rules out zoom transitions and
  `if/else` layout branches, both of which keep source and destination alive at once).
- Going off screen calls `pauseStream()`, not `stop()`: `stop()` clears `geometryTask` and `start()` guards on it
  being nil, so the pair re-downloads the URDF and re-frames the camera.
- `head_pose` is the head's transform with the daemon's `head_z_offset` subtracted — both engines end `fk` with
  `T_world_head.z -= head_z_offset` — so drawing it is that subtraction undone, and nothing else. The offset is a
  **literal 0.177**, not a robot dimension: the URDF's own rest height is 0.14957, 27 mm lower. `StewartGeometry`
  therefore carries 0.177 rather than deriving it, and `RobotSceneGraph` takes its lift from there so the head and
  the rods `PassiveJointSolver` aims at it cannot end up at two different heights. Either number alone looks
  plausible on screen — one detaches the head from the platform, the other sinks it into the body.
