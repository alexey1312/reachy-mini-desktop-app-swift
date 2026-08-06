# ReachyDesign

Design tokens and the `ReachySurface` facade. **Depends on SwiftUI and nothing else** — both `ReachyUI` and
`ReachyWidgetUI` link it, and a dependency is linked into a _target_, not into the place it is called from, so
anything heavier added here would be dragged into the widget extension too. In particular: never import `ReachyKit`.
A caller maps its own domain type onto a token (`RobotAppStatus.state` → `StatusTone`); the mapping is the caller's.

## What is here

| File                  | Holds                                                                        |
| --------------------- | ---------------------------------------------------------------------------- |
| `Space.swift`         | The 4-point layout rhythm, and the two rules for adopting it                 |
| `Radius.swift`        | Corner radii plus `Radius.rect(_:)`, the only rounded rectangle handed out   |
| `Tone.swift`          | Semantic colour roles over system styles — no palette, no `.xcassets`        |
| `Typography.swift`    | Text roles from semantic `Font`s, and `IconRatio` for glyph-as-artwork       |
| `Motion.swift`        | The three animations the app runs, named                                     |
| `Metrics.swift`       | Sizes fixed by what they represent rather than by their text                 |
| `StatusTone.swift`    | `StatusTone` + `ReachyStatusLabel`, the one shape a state caption renders in |
| `ReachySurface.swift` | `SurfaceRole` + `reachySurface(_:in:)`                                       |

## Rules

- **A call site names a role, never a material, a glass or an OS version.** `.reachySurface(.chrome, in: .capsule)`,
  not `.background(.regularMaterial, in: Capsule())`. The availability fork lives in one file.
- **Every role lays an opaque `baseFill` first, then the effect on top.** Neither glass nor a material renders in a
  headless snapshot (`RunningAppDock.swift:180-187` records the same about `.bar`). Without a fill that _does_ render,
  every surface would be invisible to the reference images and the layout and text on each card would silently lose
  their regression cover. Do not "simplify" the fill away because it looks redundant on device.
- **No `@ScaledMetric` on `Space`.** The app is 98 `Section`s over 18 `Form`s and SwiftUI already scales list metrics;
  what clips at AX5 is a fixed _size_. So each component that reads a `Metrics` constant gets its own `@ScaledMetric`
  — and at the default text size the multiplier is 1, so adopting one moves no reference image.
- **Optical adjustments stay literals.** `Space` governs the rhythm of a layout; a 1 pt gap inside the dock or a 3 pt
  inset on the joystick's arc is not rhythm. A grid that swallowed the optics would be worse than no grid.
- Nothing in this module renders a domain type. `ReachyStatusLabel` takes a `String`.

## Not here yet, and why

- **`ReachySurfaceGroup` / `GlassEffectContainer`** — a container only means something once several surfaces sit
  inside one; it belongs with the PR that applies the roles, not with the one that defines them.
- **`reachyButton` / `.buttonStyle(.glass)`** — it changes button metrics, and the snapshot simulator runs iOS 26, so
  it moves reference images. Deliberately kept out of the PR that moves none.
- **A reduce-motion resolver.** Out of scope; do not read one into `Motion`'s names.
- **A localization catalogue.** Planned to land here (both bundles link this target, so one catalogue serves the app
  and the widget), but not yet present.

## Applying a role — what to expect

- `ViewportView.swift:136` builds its shape with `RoundedRectangle(cornerRadius: 12)`, whose default style is
  `.circular`. `Radius.rect(.md)` is `.continuous`, so that one site moves its reference image when it adopts the
  token. That is the intended correction, not a regression.
- `background(_:in:)` taking a `ShapeStyle` defaults to `ignoresSafeAreaEdges: .all`; `reachySurface` uses the
  `ViewBuilder` form, which does not. A scrim that today paints into the safe area (`LogConsoleView`,
  `OnboardingFlow`, `BLEConsoleScreen`) needs its own `.ignoresSafeArea` when it adopts the role.

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
