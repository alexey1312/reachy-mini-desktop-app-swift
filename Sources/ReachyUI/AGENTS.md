# ReachyUI

Shared SwiftUI views for all platforms (macOS/iPadOS/iOS). Depends on ReachyKit only.

- Adaptive layouts, not per-platform copies; `#if os(iOS)` only for platform-exclusive APIs (Settings deep link etc.).
- All robot interaction goes through `RobotSession` / `RobotBrowser` from ReachyKit — no direct URLSession here.
