# ReachyWidgetUI

Shared widget views and App Intents. Depends on ReachyKit only; ReachyUI may depend on it, never the reverse.

- Both executable bundles must include `ReachyWidgetIntentsPackage` through their own `AppIntentsPackage`; otherwise
  configuration metadata disappears even though button intents may still run.
- `RobotAppQuery.entities(for:)` restores saved configuration: never access the network or omit requested identifiers,
  because WidgetKit prunes missing selections. Live refresh belongs in `suggestedEntities()`.
- Extension processes are disposable; persist pending and failure state in App Group stores and reload affected
  timelines rather than relying on memory.
- On iOS 18, widget and Control Centre intents cannot open the app with `openAppWhenRun`; use `widgetURL` where an
  app-opening fallback is needed.
