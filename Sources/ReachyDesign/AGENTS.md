# ReachyDesign

Design tokens and the `ReachySurface` facade. **Depends on SwiftUI and nothing else** — both `ReachyUI` and
`ReachyWidgetUI` link it, and a dependency is linked into a _target_, not into the place it is called from, so
anything heavier added here would be dragged into the widget extension too. In particular: never import `ReachyKit`.
A caller maps its own domain type onto a token (`RobotAppStatus.state` → `StatusTone`); the mapping is the caller's.

## What is here

| File                       | Holds                                                                        |
| -------------------------- | ---------------------------------------------------------------------------- |
| `Space.swift`              | The 4-point layout rhythm, and the two rules for adopting it                 |
| `Radius.swift`             | Corner radii plus `Radius.rect(_:)`, the only rounded rectangle handed out   |
| `Tone.swift`               | Semantic colour roles over system styles — no palette, no `.xcassets`        |
| `Typography.swift`         | Text roles from semantic `Font`s, and `IconRatio` for glyph-as-artwork       |
| `Motion.swift`             | The three animations the app runs, named                                     |
| `Metrics.swift`            | Sizes fixed by what they represent rather than by their text                 |
| `StatusTone.swift`         | `StatusTone` + `ReachyStatusLabel`, the one shape a state caption renders in |
| `ReachySurface.swift`      | `SurfaceRole` + `reachySurface(_:in:)`                                       |
| `ReachyBadge.swift`        | A word in a capsule, on the `.badge` surface                                 |
| `ReachySurfaceGroup.swift` | `GlassEffectContainer` where there is one, the content itself below          |
| `ReachyButton.swift`       | `ButtonEmphasis` + `reachyButton(_:)` — and why it has no glass tier         |
| `ReachyChrome.swift`       | The iOS 26 bar behaviours, each a no-op below the floor                      |

## Rules

- **A call site names a role, never a material, a glass or an OS version.** `.reachySurface(.chrome, in: .capsule)`,
  not `.background(.regularMaterial, in: Capsule())`. The availability fork lives in one file.
- **Every role lays an opaque `baseFill` first, then the effect on top.** Neither glass nor a material renders in a
  headless snapshot (`RunningAppDock.swift:172-178` records the same about `.bar`). Without a fill that _does_ render,
  every surface would be invisible to the reference images and the layout and text on each card would silently lose
  their regression cover. Do not "simplify" the fill away because it looks redundant on device.
- **Glass is invisible headless, but what it wraps is not.** `glassEffect` renders its content vibrantly, and that
  _does_ come out in a reference image: measured on the iOS 26 simulator, `.red`, `.orange`, `.green` and `.secondary`
  text inside one all render black, while `.tint` survives. Modifier order makes no difference — inside or outside the
  surface, the result is identical. So the effect goes **under** the content, never around it, and `.badge` takes
  neither glass nor material: a marker inside a card floats over nothing, and carrying a colour is the whole of its job.
- **Three more things glass does headless, each measured rather than assumed.** They are why this module looks more
  conservative than the plan:
  1. **`.buttonStyle(.glass)` blanks the whole capture.** Not "does not render" — a screen carrying one comes out
     empty apart from its toolbar, which is a separate pass. Recorded the onboarding suite twice to confirm: every
     reference blank with it, every reference complete without it, nothing else changed. `reachyButton` therefore has
     no glass tier, and roughly sixty references keep their cover.
  2. **Glass over an edge with nothing behind it renders as a black-red-green smear.** The dock's shape crosses the
     safe area, and its reference caught exactly that. The same glass over the viewport's chrome, which stays inside
     the screen, is clean. Hence `.window`, a role that is `.scrim` minus the glass.
  3. **Glass laid over a `Color.clear` does the same** — there is no backdrop to refract. It goes over the opaque
     `baseFill`, which is where `ReachySurfaceFill` puts it.
- **A surface is a shape, not a `Color`.** A `Color` is flexible in both axes, so one carrying `ignoresSafeArea`
  expands to the entire safe-area container rather than to the thing it backs. Mounted under a `safeAreaInset` — which
  draws over the content — that painted whole screens in the window colour. Use `ReachySurfaceFill`, or `reachyScrim`,
  which asks for the inset by name because `reachySurface` uses the `ViewBuilder` form of `background` and stops at
  the safe area where `background(_:)` taking a `ShapeStyle` did not.
- **No `@ScaledMetric` on `Space`.** The app is 98 `Section`s over 18 `Form`s and SwiftUI already scales list metrics;
  what clips at AX5 is a fixed _size_. So each component that reads a `Metrics` constant gets its own `@ScaledMetric`
  — and at the default text size the multiplier is 1, so adopting one moves no reference image.
- **Optical adjustments stay literals.** `Space` governs the rhythm of a layout; a 1 pt gap inside the dock or a 3 pt
  inset on the joystick's arc is not rhythm. A grid that swallowed the optics would be worse than no grid.
- Nothing in this module renders a domain type. `ReachyStatusLabel` takes a `String`.
- **A `Tone` colours a foreground, not a fill.** `ReachyBadge` puts the tone on its text and takes the `.badge`
  surface underneath, which is what let the app's one pinned `.foregroundStyle(.white)` go: white read only against a
  capsule filled with `.tint`, and a light tint in a dark appearance left white on light. Filling a shape with a tone
  brings the pinned foreground back with it.
- **A `static func` returning one of these views needs `@MainActor`.** `View` carries that isolation in Swift 6, so a
  nonisolated factory building a `ReachyStatusLabel` compiles with an `ActorIsolatedCall` warning
  (`RunningAppCaption.label`). The value-only mappings beside it stay off the actor.

## Not here yet, and why

- **A glass tier on `reachyButton`.** Not deferred for taste — it blanks the capture (see the rules above). Revisit
  only with evidence that a screen carrying one snapshots whole.
- **`glassEffectID` morphing between screens.** Worth having only once a layout is built around it, and there is no
  equivalent below the floor.
- **A reduce-motion resolver.** Out of scope; do not read one into `Motion`'s names.
- **A localization catalogue.** Planned to land here (both bundles link this target, so one catalogue serves the app
  and the widget), but not yet present.

## Applying a role — what happened

All seven ad-hoc sites now name a role: the viewport's three pieces of chrome (`.chrome`), the log console, the BLE
console and the onboarding footer (`reachyScrim`), and the running-app strip (`.window`). What to expect from the next
one:

- `ViewportStatus.loading` moved its reference image because `Radius.rect` is `.continuous` where
  `RoundedRectangle(cornerRadius: 12)` defaulted to `.circular`. That is the intended correction, not a regression.
- `background(_:in:)` taking a `ShapeStyle` defaults to `ignoresSafeAreaEdges: .all`; `reachySurface` uses the
  `ViewBuilder` form, which does not. A scrim that today paints into the safe area (`LogConsoleView`,
  `OnboardingFlow`, `BLEConsoleScreen`) needs its own `.ignoresSafeArea` when it adopts the role.

## Both appearances, and what glass does to the dark half

Every preview is now captured twice — `Apps/ReachyUISnapshotTests/PreviewTests.stencil` forks Prefire's built-in
test template and loops the capture over `[.light, .dark]`, naming the dark file with a `-dark` suffix. The light
names are untouched, which is why adopting it re-recorded nothing: 500 new files, 0 modified.

The appearance travels as a **trait**, not as `preferredColorScheme` (which wants a window scene the snapshot host has
no equivalent of) and not as `\.colorScheme` in the environment (which moves SwiftUI's own colours and leaves
UIKit-backed ones light). swift-snapshot-testing feeds the collection to `setOverrideTraitCollection`, which reaches
both halves.

**`glassEffect` renders a light surface in both appearances, and it is opaque.** Measured on `Design — surfaces`: in
the dark capture `badge` and `window` flip correctly while `chrome`, `card` and `scrim` stay white capsules with
their white labels invisible on them. The two that flip are exactly the two roles with `glass == nil`. It is not the
trait failing to arrive: re-recording that gallery with the _simulator_ switched to dark produced both images
byte-for-byte identical to the run on a light simulator, so the injected trait is what decides and glass ignores it
either way.

What that means when reading a dark reference:

- Over a `.chrome`, `.card` or `.scrim` surface, a dark capture shows **the snapshot's white glass, not the device's**.
  Light-on-that is invisible in the image and legible on hardware. Do not "fix" a foreground because it vanished there.
- The roles that carry no glass — `.badge`, `.window` — and everything outside a surface are truthful, and that is
  where the dark half earns its keep: `LogConsoleView`'s level palette, the status captions, every screen background.
- A dark reference is therefore evidence about _content_, and evidence about glass only on device.

## Previews

`Previews/` is excluded from the SwiftPM target and compiled only by the Xcode targets in `Apps/` — `#Preview` is an
external macro that ships inside Xcode's SDKs, not in the pinned swift.org toolchain. The same rules as
`ReachyUI/Previews` apply: anything a preview body names must be visible target-wide, because Prefire copies the body
into a generated file.

Adding a preview directory here means editing **six** files, not the five a target's wiring usually takes:
`Package.swift`, `Apps/Project.swift` (`sources` of _both_ preview-hosting targets), `Apps/.prefire.yml` (`sources`
and `testable_imports` in _both_ sections), this file, and `mise.toml` — where `prefire playbook` is handed an
explicit directory list in **two** tasks (`project` and `storybook`). Miss the `.prefire.yml` `sources` entry and the
previews compile while generating no tests at all, which reads as everything passing. Miss `mise.toml` and the
gallery is simply absent from the storybook, with no error anywhere.
