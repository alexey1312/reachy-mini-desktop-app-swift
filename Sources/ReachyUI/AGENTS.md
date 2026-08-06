# ReachyUI

Shared SwiftUI views for all platforms (macOS/iPadOS/iOS). Depends on ReachyKit and ReachyMedia (WebRTC camera).

- Adaptive layouts, not per-platform copies; `#if os(iOS)` only for platform-exclusive APIs (Settings deep link etc.).
- `horizontalSizeClass` is unavailable on macOS — guard size-class branching with `#if os(macOS)` (always regular there).
  The root used to build a two-column `HStack` for a regular width and hide the Live tab on a compact one;
  `.tabViewStyle(.sidebarAdaptable)` does that adaptation itself, and it is iOS 18 / macOS 15, not an iOS 26 API.
  Reaching for the size class to fork a _layout_ is still a sign the layout is being forked rather than adapted.
- **There is exactly one size-class branch, in `FloatingViewportModifier`, and it is not a layout fork.** The floating
  viewport asks a different question: not "how wide is this" but **"does the shell draw a tab bar or a sidebar"**. A
  sidebar keeps the Live tab beside every other destination, so there is nothing to float out of it and no second
  place the viewport could go; a tab bar hides it, which is the whole reason the window exists. `.sidebarAdaptable`
  makes that decision on the size class and offers no way to ask what it decided, so the modifier reads the same input
  and writes `FloatingViewportModel.hasTabBar`. False collapses `placement` to `.inline` everywhere — the exact
  behaviour this target had before the window existed, including `viewportIsOnScreen`. This entry used to say nothing
  in the target branched on the size class; do not "restore" it by deleting the branch.
- **Navigation is `ReachyRouter` plus two destinations.** `ReachyRootView` owns what outlives a screen and picks the
  gate or the shell; `Navigation/` holds the router, the effect cluster and the sheet stack; `Shell/` holds the five
  tabs. The five are unconditional — a tab that comes and goes forces the shell to catch its disappearance and drag
  the selection elsewhere, which is what `onChange(of: offersLiveTab)` used to do. An unavailable feature renders an
  unavailable state inside its own tab instead.
- **`.unreachable` belongs to the shell, not the gate.** Only `.idle` and `.connecting` show the gate. A network blip
  must not pull the tab bar out from under a finger, and the robot screen already reports the state in place.
- **The gate's fork has progress conditions, and they only ever delay.** For `.connected`, `isConnectedEnough` waits
  until `progress.displayed` has caught the session and `progress.holdsGate` is false. Crossing that line throws the
  gate's whole subtree away, so the equality check keeps the child phase observer alive long enough to see the final
  transition, and the hold then keeps its three checkmarks on screen — on a local network the stages can resolve in
  tens of milliseconds and otherwise read as an unexplained flash. `.unreachable` bypasses both conditions: it is a
  later network blip that belongs to the shell and must never resurrect the gate.
  `ConnectProgressModel` therefore lives in the root, not in the gate: it holds each stage on screen for a floor of
  `dwell`, holds one further `dwell` after the last frame, and releases on a `maxHold` ceiling that depends on
  nothing. At `dwell: .zero` it never holds at all, which is what every preview injects and why the reference images
  behave as they did before it existed.
- **Anything conditional on "an attempt is running" mounts and unmounts every 10 s.** The candidate sweep beats on
  that period and an automatic attempt falls back to `.idle` rather than `.failed`, so the phase walks
  `idle → handshaking → idle` forever while nothing answers. This was a reported bug — the screen visibly compressed
  and expanded — and it had **two** sources, not one: the connection stepper as a form section, and the `lastError`
  section, because `beginAttempt` clears `lastError` while `failAttempt` sets it for automatic attempts too (its
  `guard !automatically` comes after the assignment). Fixing only the first leaves the symptom intact. The rail is now
  mounted for the whole life of the gate, its detail slot reserves one caption line whether or not there is anything
  to say, and `lastError` is shown only once `automaticConnectionAllowed` is false. Before adding anything to this
  screen, ask what it does on that heartbeat.
- Leaves stay injectable rather than reading the router: `ConnectionScreen.showRemoteRobots` is optional because its
  absence is what hides `YourReachiesSection` in previews. The router is the shell's business.
- All robot interaction goes through `RobotSession` / `RobotBrowser` from ReachyKit — no direct URLSession here.
- Screen logic belongs in a `@MainActor @Observable` model beside the view (`MovesModel`, `LogConsoleModel`), covered
  by `Tests/ReachyUITests`; the view stays thin. `@Observable` does honour `didSet`, so derived caches can live there.
- Content catalogues use `contentLoading(isPresented:title:)` for their initial or uncached load. The model must
  distinguish "never answered" from a real empty result and expose loading before `.task` gets its first turn, so the
  first frame never lies with an empty-state. A refresh keeps any rows already on screen; only a request with no data
  gets the centred, lightly robot-themed label. Every such state gets a frozen preview and recorded snapshots.
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

## Strings

Project rule 9 in the root `AGENTS.md` is the whole of it: `.reachy("…")` where SwiftUI takes a
`LocalizedStringResource`, `String(localized: .reachy("…"))` where the value has to stay a `String`. Two things this
target learned doing it:

- **A caption type, not `String(describing:)`.** `DaemonStateCaption` maps the generated
  `Components.Schemas.DaemonState` onto words; `RunningAppCaption` does the same for a process state. Both live here
  rather than in `ReachyKit`, because `ReachyKit` does not link `ReachyDesign` and must not start — a caller maps its
  own domain type onto a presentation value, never the reverse.
- **A sentence is one key.** Prose split across `+` for the sake of the 120-column rule became one literal with
  `// swiftlint:disable:next line_length` above it. Two half-keys cannot be reordered by a translator, and the
  fragments collide as generated symbols with whatever else ends in the same words.

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
- **A tab whose content is loaded by a `.task` has no usable root capture, only a standalone one.** The shell builds
  all five tabs at once, and whichever loses that race is caught mid-layout. Settings comes out pure white on iPhone
  while rendering fine on iPad; Moves came out on iPad with its spinner but with the caption under it missing, and
  only a later run — one preview added elsewhere, timings shifted — produced the full frame. The tell is in the
  image: bare tab-bar glyphs instead of labels, or a state missing half of itself. Neither `SettingsScreen` nor
  `MovesTab` can be handed a settled model from `PreviewScene.root`, because the root builds the shell and the shell
  builds the tab — threading a seam through both for a preview is not worth it. So capture those screens standalone
  (`SettingsPreviews`, `MovesScreenPreviews`) and capture _placement_ from a state that needs no `.task` at all
  (`Root — relay moves tab`, which renders `MovesUnavailableView`). A blank or half-drawn reference is worse than a
  missing one: it reads as coverage and passes any change.
- Not covered, deliberately: `SceneViewport` in `.ready` — a bare `RealityView`, which renders nothing meaningful
  headless, so its overlay phases are what get snapshotted.
- **`CameraViewport` in `.streaming` used to be on that list and is not any more.** The reasoning was that the video
  is a Metal-backed `RTCMTLVideoView` and captures as an empty rectangle — true, and beside the point once the phase
  grew chrome of its own. The joystick and the return-to-neutral button draw over that empty rectangle perfectly
  well, and the button is _conditional_: a reference for the turned state alone cannot tell a conditional control
  from a permanent one, so `Camera — facing forward` exists to capture its **absence**. A black frame with controls
  on it is the intended image. The rule this leaves behind: a phase is uncapturable only while nothing but the
  unrenderable layer is in it.
- One `RobotSceneModel` per preview: `ReachyScene/AGENTS.md` requires exactly one live `RealityView` per model.
- **Navigation chrome does not stay inside a preview card.** SwiftUI hoists `.toolbar` and
  `.searchable` out of the storybook's scaled cards into the app's own bars, even though each
  preview brings its own `NavigationStack` — this is the limitation Prefire records as
  "NavigationView in Preview not supported for Playbook". The storybook hides its root bars to
  absorb it; `LogConsoleScreen`'s search field still floats over the catalogue, which is cosmetic
  and not worth contorting the screen for. Snapshots are unaffected — they capture the title _and_
  the toolbar items, so `RobotScreen`'s Settings gear and `MovesScreen`'s Refresh are covered.
  Only the storybook hoists.
