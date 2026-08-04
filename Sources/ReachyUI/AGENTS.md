# ReachyUI

Shared SwiftUI views for all platforms (macOS/iPadOS/iOS). Depends on ReachyKit and ReachyMedia (WebRTC camera).

- Adaptive layouts, not per-platform copies; `#if os(iOS)` only for platform-exclusive APIs (Settings deep link etc.).
- `horizontalSizeClass` is unavailable on macOS — guard size-class branching with `#if os(macOS)` (always regular there).
- All robot interaction goes through `RobotSession` / `RobotBrowser` from ReachyKit — no direct URLSession here.
- Screen logic belongs in a `@MainActor @Observable` model beside the view (`MovesModel`, `LogConsoleModel`), covered
  by `Tests/ReachyUITests`; the view stays thin. `@Observable` does honour `didSet`, so derived caches can live there.
- Deployment floor is iOS 18 / macOS 15 (`Package.swift`, `Apps/Project.swift`), set by `RealityView`.
  `ScrollPosition`, `onScrollPhaseChange` and `onScrollGeometryChange` are available; the zero-height sentinel row in
  `LogConsoleScreen` predates the bump and is not a required pattern.
