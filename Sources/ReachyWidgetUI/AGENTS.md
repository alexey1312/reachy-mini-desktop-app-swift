# ReachyWidgetUI

Shared widget views and App Intents. Depends on ReachyKit and ReachyDesign; ReachyUI may depend on it, never the
reverse.

- **What both surfaces draw lives here, and moves down rather than up.** An extension process cannot link `ReachyUI`,
  so a view the app and the widget both render belongs in this target: `AppArtwork` and `AppArtworkTile` first,
  `AppRowLabel` after it. The alternative is two copies that drift the first time one of them is edited — which is
  exactly what the dock strip and the launcher tile had become.
- `AppRowLabel` takes an `AppRowLayout` preset rather than loose numbers, and a `ReachyStatusLabel` already built.
  Each caller keeps its own mapping from a domain state onto a `StatusTone`, so this target never grows a rule about
  what "running" should look like — `RunningAppCaption` owns that for the app, `RobotAppTileView.statusTone` for the
  widget, and they disagree on purpose: a tile is already tinted and badged, and a fourth green signal would turn the
  grid into a status board.
- Both executable bundles must include `ReachyWidgetIntentsPackage` through their own `AppIntentsPackage`; otherwise
  configuration metadata disappears even though button intents may still run.
- `RobotAppQuery.entities(for:)` restores saved configuration: never access the network or omit requested identifiers,
  because WidgetKit prunes missing selections. Live refresh belongs in `suggestedEntities()`.
- Extension processes are disposable; persist pending and failure state in App Group stores and reload affected
  timelines rather than relying on memory.
- On iOS 18, widget and Control Centre intents cannot open the app with `openAppWhenRun`; use `widgetURL` where an
  app-opening fallback is needed.
- **The views localize, the intents do not — and that split is deliberate.** Everything rendered goes through
  `.reachy(_:)` like the rest of the app, but `AppIntent.title`, `DisplayRepresentation` and the widgets'
  `configurationDisplayName` stay bare `LocalizedStringResource` against the main bundle: that metadata is baked into
  `Metadata.appintents` at build time, where a runtime bundle URL has nothing to resolve against. Reasoning in
  `Sources/ReachyDesign/AGENTS.md`.
