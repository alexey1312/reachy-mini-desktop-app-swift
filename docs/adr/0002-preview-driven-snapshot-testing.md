# ADR 0002: Preview-driven snapshot testing

- Status: Accepted
- Date: 2026-08-04

## Context

Until now the project deliberately tested _around_ its views. `Sources/ReachyUI/AGENTS.md` puts screen logic in a
`@MainActor @Observable` model beside the view and covers that model in `Tests/ReachyUITests`, and the log-console
design spec states the reason plainly: "The screen cannot be exercised end-to-end without a wireless robot, which is
why the model carries the logic."

That leaves layout as the one layer with no regression cover. It also leaves a specific gap: `ReachyRootView` switches
between a tab bar and a two-column split on `horizontalSizeClass`, and the iPad branch has never been verified — the
phase-0 report closed with the iPad checklist unticked ("no device at hand; same binary, low risk").

There were no `#Preview` blocks anywhere in the repository, so this is a green field rather than an extension of
existing preview coverage.

## Decision: snapshot the views, from previews

Adopt [Prefire](https://github.com/BarredEwe/Prefire). It reads `#Preview` blocks and generates one XCTest per preview
file, capturing each through swift-snapshot-testing. The same previews feed a browsable playbook, which the
`ReachyStorybook` app target hosts.

Two device configurations are rendered per preview — `iPhone 16 Pro` and `iPad Pro 11` — from a single pinned
simulator. The iPad configuration carries `horizontalSizeClass: .regular`, so it is what actually exercises the
two-column layout.

This does not displace the model-first rule. Model tests still own behaviour; snapshots own appearance. A preview
asserts nothing about logic — it fixes a model in one state and records what that state looks like.

## Decision: previews are excluded from the SwiftPM target

`Sources/ReachyUI/Previews/` sits beside the views but is listed in `exclude:` in `Package.swift`. Only the Xcode
targets under `Apps/` compile it.

`#Preview` is an external macro whose implementation, `libPreviewsMacros.dylib`, ships inside Xcode's platform SDKs
and not in a swift.org toolchain. This project pins Swift through swiftly and CI installs the swift.org 6.3
toolchain, so a `#Preview` under any SwiftPM target fails the build with "plugin for module 'PreviewsMacros' not
found" — breaking `mise run build`, `mise run test` and the `build-test` CI job. Excluding the directory keeps the
files next to the views they document while leaving the package build untouched.

The same constraint keeps Prefire itself out of `Package.swift`: its generated tests and its `PlaybookView` both call
UIKit unconditionally, so the library does not build for macOS at all. It is declared in `Apps/Project.swift`, and
both new targets are iOS/iPadOS only.

## Decision: previews are frozen, never awaited

Every preview hands its screen a model that is already in its end state, and `\.reachyPreviewMode` suppresses the
live work screens start on appear (Bonjour browsing, the log and teleop WebSockets, viewport attachment).

Prefire captures synchronously, and the delay knob it offers — `.snapshot(delay:)` — lives in the Prefire library,
which ReachyUI cannot import without breaking the macOS build. There is therefore no way to wait for a `.task` to
settle. Project rule 7 already forbids sleeping before an assertion; here the constraint is stronger, because the
first rendered frame has to be the final one.

## Consequences

- Reference images live under `Apps/ReachyUISnapshotTests/__Snapshots__` and are tracked with Git LFS. `.gitattributes`
  was added before the first image, and `bootstrap.sh` runs `git lfs install --local`.
- Snapshots run on one pinned simulator and OS (`mise run test:snapshots`). A different iOS runtime renders text
  differently, so an Xcode upgrade means re-recording; that is what `mise run test:snapshots:record` is for.
- No CI job yet. Local Xcode is 26.4.1 and CI is pinned to 26.2, so references recorded on one would fail on the
  other. Adding the job means first agreeing on a runtime for both.
- Views gained initialisers with defaulted model parameters. Production call sites are unchanged.
- `SceneViewport` in `.ready` and `CameraViewport` in `.streaming` are not covered: one is a bare `RealityView`, the
  other a Metal-backed `RTCMTLVideoView`, and neither renders anything meaningful headless. Their overlay phases are.
