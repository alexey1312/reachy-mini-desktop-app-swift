# ReachyUI

Shared SwiftUI views for all platforms (macOS/iPadOS/iOS). Depends on ReachyKit and ReachyMedia (WebRTC camera).

- Adaptive layouts, not per-platform copies; `#if os(iOS)` only for platform-exclusive APIs (Settings deep link etc.).
- `horizontalSizeClass` is unavailable on macOS — guard size-class branching with `#if os(macOS)` (always regular there).
- All robot interaction goes through `RobotSession` / `RobotBrowser` from ReachyKit — no direct URLSession here.
- Screen logic belongs in a `@MainActor @Observable` model beside the view (`MovesModel`, `LogConsoleModel`), covered
  by `Tests/ReachyUITests`; the view stays thin. `@Observable` does honour `didSet`, so derived caches can live there.
- `Section` has no title-plus-footer overload: `Section("X") { … } footer: { … }` fails to compile with a misleading
  "generic parameter 'Content' could not be inferred". Either `Section("X") { … }` or the full
  `Section { … } header: { Text("X") } footer: { … }`.
- A container view taking a closure argument _and_ two trailing `@ViewBuilder`s trips SwiftLint's
  `multiple_closures_with_trailing_closure`. Pass the extra behaviour as a child view instead
  (`OnboardingBackButton`), not as a third closure.
- `background(_:)` defaults to `ignoresSafeAreaEdges: .all`, so a full-bleed backdrop also paints the inset the
  floating tab bar sits in — bottom on iPhone, top on iPad. That bar is glass and renders whatever it finds there, so
  it turns dark on that one tab, a frame behind the switch. Neither viewport paints a backdrop any more: the 3D scene
  and the camera's letterbox both take the system background, so the chrome over them stays legible in both
  appearances. **Do not pin a colour under adaptive chrome** — every such backdrop drags a pinned foreground along
  with it, and then neither half can be removed alone. The Live tab's `Color.black` forced
  `toolbarColorScheme(.dark)` to keep the title readable (drop one and the title goes white-on-white or
  black-on-black); the camera's forced a white `Connecting…` for the same reason. `RTCMTLVideoView` clears its own
  unfilled area, so the video never needed the SwiftUI backdrop — that one only ever painted the safe-area insets.
- Deployment floor is iOS 18 / macOS 15 (`Package.swift`, `Apps/Project.swift`), set by `RealityView`.
  `ScrollPosition`, `onScrollPhaseChange` and `onScrollGeometryChange` are available; the zero-height sentinel row in
  `LogConsoleScreen` predates the bump and is not a required pattern.

## Previews and snapshots

`Previews/` sits here but is **excluded from the SwiftPM target** (`Package.swift`) and compiled only by the Xcode
targets in `Apps/`. `#Preview` is an external macro implemented by `libPreviewsMacros.dylib`, which ships inside
Xcode's platform SDKs and not in the pinned swift.org toolchain — a `#Preview` anywhere under a SwiftPM target breaks
`mise run build`, `mise run test` and CI with "plugin for module 'PreviewsMacros' not found".

Adding a screen (project rule 8) means: a preview per state in `Previews/<Screen>Previews.swift`, whatever seam and
`#if DEBUG` factory those states need, `mise run test:snapshots:record`, and `git add` on the PNGs.

- Preview files use `@testable import ReachyUI`; that is why `ENABLE_TESTABILITY` is set for the whole Xcode project.
- **Prefire reads previews off the filesystem; Xcode compiles the file list Tuist baked in.** A new file under
  `Previews/` is therefore picked up by the generator but not compiled until `mise run project` runs again — which is
  why the snapshot tasks depend on it. A bare `xcodebuild` skips that and fails with "cannot find … in scope".
  **Deleting** a file needs the same regeneration, and fails less legibly: `Build input file cannot be found`, which
  reads as a broken checkout rather than a stale file list.
- Anything a preview body references must be visible target-wide, because Prefire copies the body into a separate
  generated file. Shared wrappers live in `PreviewScene`; a `private` helper compiles locally and breaks the test.
- **A preview with no `traits:` is captured at full device size.** Prefire defaults the trait list to `.device`
  (`RawPreviewModel.isScreen`), and that device trait is what carries `horizontalSizeClass` — so it is what makes the
  iPad snapshot exercise the regular-width layout. Components opt out with `traits: .sizeThatFitsLayout`.
- **A preview must be final on its first frame.** Prefire captures synchronously and its `.snapshot(delay:)` modifier
  lives in a module this target cannot import without breaking the macOS build. Never rely on a `.task` completing —
  hand the view a model that is already in its end state (`AudioSettingsModel.preview()`, `RobotSession.preview()`).
- Model preview factories live **in the model's own file** under `#if DEBUG`, not in `Previews/`: they write members
  that are `private` to that file, and `@testable` does not reach `private`.
- Screens take their model through an initialiser with a default (`init(session:model:)`), so production call sites
  are unchanged and previews inject a frozen one.
- A defaulted argument whose value is `@MainActor` (`= SpikeModel()`, `= .preview()`) compiles in the SwiftPM targets
  but not in the `Apps/` ones, where it is evaluated nonisolated. Use `nil` and resolve it in the body.
- A model that already takes a factory closure (`OnboardingModel(session:)`, `BLEConsoleModel(link:)`) needs no new
  seam — hand it a `BLELink.preview(…)`, which sits on an inert `PreviewBLETransport` and is assigned its state
  directly. Building the link is not enough on its own: `OnboardingModel.session` is only set by `beginScan()`, which
  is the CoreBluetooth call a preview must not make, so the factory assigns it.
- A screen whose `.task` guards on `model == nil` needs no `reachyPreviewMode` check — injecting the model is what
  makes it inert. Add the guard only where the effect runs unconditionally (`WiFiSettingsCard`, `LogConsoleScreen`).
- Not covered, deliberately: `SceneViewport` in `.ready` (a bare `RealityView`) and `CameraViewport` in `.streaming`
  (Metal-backed `RTCMTLVideoView`). Neither renders anything meaningful headless — snapshot their overlay phases.
- One `RobotSceneModel` per preview: `ReachyScene/AGENTS.md` requires exactly one live `RealityView` per model.
- **Navigation chrome does not stay inside a preview card.** SwiftUI hoists `.toolbar` and
  `.searchable` out of the storybook's scaled cards into the app's own bars, even though each
  preview brings its own `NavigationStack` — this is the limitation Prefire records as
  "NavigationView in Preview not supported for Playbook". The storybook hides its root bars to
  absorb it; `LogConsoleScreen`'s search field still floats over the catalogue, which is cosmetic
  and not worth contorting the screen for. Snapshots are unaffected — they capture the title _and_
  the toolbar items, so `RobotScreen`'s Settings gear and `MovesScreen`'s Refresh are covered.
  Only the storybook hoists.
