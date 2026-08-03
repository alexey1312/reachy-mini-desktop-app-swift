# Log console: copy, export and console revamp

- Status: Approved
- Date: 2026-08-03

## Context

`LogConsoleScreen` tails `/logs/ws/daemon` and renders plain journal lines. It has no way to get a log off the
device, which is the whole point of reading a daemon log: attaching it to a bug report. Three further problems make
the current screen weak as a diagnostic tool.

- All state lives in the view (`lines`, `paused`, buffer trimming). Nothing is unit-testable, and there is no single
  place to ask for "the current log text" that copy and export both need.
- Pause drops data. `if paused { continue }` discards stream lines instead of buffering them, so pausing punches a
  hole in the log — and that hole would ship with the export.
- A 2000-line flat list with no search, no level filter and no visual weighting makes finding an error slow.

The endpoint only exists on a real robot: `/logs/ws/daemon` is mounted at the app root and served only with
`--wireless-version`; the simulator rejects the upgrade with HTTP 403. Logic must therefore be verifiable without a
live stream.

## Decision

Move console state into `LogConsoleModel` (`@MainActor @Observable`) in ReachyUI, mirroring the existing
`MovesModel` + `MovesModelTests` pattern. The view stays thin; every behaviour below is unit-tested through the
model. The buffer stays out of ReachyKit: search and filtering are UI state, and `LogStreamClient` already delivers
what the model needs.

### Entry model

```swift
struct LogEntry: Identifiable, Sendable {
    let id: Int
    let timestamp: String?
    let message: String
    let level: LogLevel
    let text: String
}

enum LogLevel: Int, CaseIterable, Sendable { case debug, info, warning, error }
```

`text` is the untouched source line — copy and export ship exactly what the daemon sent. `timestamp` is the
`short-iso` prefix journalctl emits; `message` is the remainder.

Level is inferred from message content: `ERROR` / `CRITICAL` / `FATAL` / `Traceback` → error, `WARN` / `WARNING` →
warning, `DEBUG` → debug, everything else → info. Journalctl's `short-iso` format carries no priority field and the
daemon is a Python service, so the level is only available as a token inside the message. Matching is
case-sensitive on upper-case tokens to avoid classifying prose such as "error rate" as an error.

### Pause

Pause stops the display, not ingestion. Incoming lines accumulate in `pending`; the toolbar shows a `+N` badge;
Resume appends them in order. The log stays complete on screen and in the export.

### Buffer

Capacity is user-selectable (1 000 / 5 000 / 20 000, default 5 000) via a toolbar menu, persisted with
`@AppStorage`. Overflow trims from the head, as today.

### Filtering

`.searchable` text query (case-insensitive, matched against `text`) plus a level picker (All / Info+ / Warning+ /
Errors). The model keeps `visible` as a maintained cache: an incoming entry is tested against the active filter and
appended when it matches; a full recompute happens only when the query or level changes. Recomputing the whole
filter per arriving line would not hold up at 20 000 lines.

### Presentation

Monospaced text is kept. Timestamp renders `.secondary`; error red, warning orange, debug muted. Auto-scroll
follows the tail until the user scrolls away, at which point a "Jump to latest" control appears. The subtitle shows
`N lines`, or `N of M` while a filter is active.

### Copy

Toolbar "Copy all" copies the visible (filtered) log. A row context menu copies a single line. A `Clipboard.copy(_:)`
helper holds the only platform branch: `#if os(iOS)` UIPasteboard, `#else` NSPasteboard.

### Export

`ShareLink(item: LogExport)` where `LogExport: Transferable` holds a snapshot of the visible entries (a COW array
reference, cheap to construct on every toolbar render) and serializes lazily inside `DataRepresentation`, so the
text is built only when the user actually shares. Suggested file name
`reachy-daemon-<host>-<yyyyMMdd-HHmmss>.txt`, content type `UTType.plainText` — more reliably handled by the iOS
share sheet than a `.log` extension.

The file opens with a metadata header, because an exported log is read detached from the app and must state what was
captured and whether a filter truncated it:

```
# Reachy Mini daemon log
# robot: 10.42.0.1:8000
# exported: 2026-08-03T12:00:00Z
# lines: 1234 of 5000 (level: warning+, search: "motor")
```

## Testing

`Tests/ReachyUITests/LogConsoleModelTests.swift`:

- level and timestamp parsing, including a line with no recognizable level and a line with no timestamp prefix
- buffer trims to capacity from the head; lowering capacity trims immediately
- pause accumulates without loss; resume appends pending in arrival order
- level filter and search query, individually and combined
- export text starts with the header and contains every visible line
- copy-all returns the filtered set, not the whole buffer

Stream behaviour itself stays covered by the existing `LogStreamClientTests`. The screen cannot be exercised
end-to-end without a wireless robot, which is why the model carries the logic.

## Consequences

- Copy and export read one source of truth, so what the user sees is what leaves the device.
- Pause becomes safe to use during an incident instead of a way to lose the lines that mattered.
- `LogConsoleScreen` grows a filter bar and a toolbar menu; the model absorbs the state that would otherwise land in
  the view.
- Level detection is a heuristic over message text and will misclassify daemon messages that do not spell their
  level. Filtering is a convenience, not a guarantee — "All" remains the default so nothing is hidden by surprise.
