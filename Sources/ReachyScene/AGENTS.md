# ReachyScene

RealityKit rendering of the robot, driven by the state stream. Depends on ReachyKit. Read-only — nothing here
ever sends the robot a command.

- An `Entity` has one parent, so there must be **exactly one live `RealityView` per `RobotSceneModel`** — a second
  one silently steals the robot from the first. Move the view; never mount two (this rules out zoom transitions and
  `if/else` layout branches, both of which keep source and destination alive at once).
- Going off screen calls `pauseStream()`, not `stop()`: `stop()` clears `geometryTask` and `start()` guards on it
  being nil, so the pair re-downloads the URDF and re-frames the camera.
