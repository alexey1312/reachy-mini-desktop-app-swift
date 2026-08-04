# ReachyMini — Agent Instructions

Native Swift client (macOS/iPadOS/iOS) for the Reachy Mini Wireless robot. Pure network client to the robot daemon's
HTTP/WebSocket API. Swift 6, strict concurrency.

## Environment Setup — MANDATORY

The development environment is installed **only** via:

```bash
./bootstrap.sh
```

It installs all pinned tools (swiftformat, swiftlint, hk, dprint, actionlint, git-cliff, xcsift, tuist) through the
self-contained `./bin/mise` binary and wires git hooks (`core.hooksPath .githooks`).

- **Never** install tools globally (`brew install swiftlint`, `npm i -g`, etc.).
- **Never** call tools bare (`swift build`, `swiftlint`) — always `./bin/mise run <task>` or `./bin/mise x -- <tool>`,
  which guarantees pinned versions and PATH.
- Swift itself is managed by swiftly via `.swift-version`, not by mise.
- Tool versions are pinned in `mise.toml` + `mise.lock`. After editing `[tools]`: `trash mise.lock && ./bin/mise lock`.
- The `hk` version in `mise.toml` must match the `hk@X.Y.Z` package URI in `hk.pkl` (bump together).
- `mise run project` (tuist generate) needs a one-time `./bin/mise x -- tuist auth login` — the project is connected
  to tuist.dev (`alexey1312/reachy-mini-desktop-app-swift` in `Apps/Tuist.swift`).

## Quick Reference

```bash
./bin/mise run build          # Debug build (piped through xcsift)
./bin/mise run test           # All tests, parallel
./bin/mise run test:filter T  # Filter tests
./bin/mise run lint           # SwiftLint --strict + actionlint
./bin/mise run format         # Format all (hk fix --all)
./bin/mise run format-check   # CI formatting check
./bin/mise run project        # tuist generate (Apps/)
./bin/mise run sim-daemon     # Simulated robot daemon (MuJoCo, LAN-reachable)
./bin/mise run update-spec    # Refresh + normalize daemon OpenAPI spec
```

`build` / `test` are SwiftPM only — they never compile `Apps/ReachySpike`. Check app-target code with
`xcodebuild -workspace Apps/ReachyMiniApps.xcworkspace -scheme ReachySpike -destination '...' -skipPackagePluginValidation build`.
`test:filter` matches type names (`RobotSessionAudioTests`), not `@Suite` display names.
`mise run lint` pipes through xcsift, which can truncate and report `status: incomplete` while hiding violations —
rerun `./bin/mise x -- swiftlint lint --strict Sources Tests Apps/ReachySpike` to see them.

## Project Context

|              |                                                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------- |
| Robot API    | `http://<robot>:8000/api`, OpenAPI 3.1 spec committed at `Sources/ReachyKit/openapi.json`                           |
| State stream | WebSocket `/api/state/ws/full`, 10 Hz by default (not in the OpenAPI spec — hand-written client)                    |
| Upstream     | `pollen-robotics/reachy-mini-desktop-app` + `pollen-robotics/reachy_mini` — **specification only, never copy code** |
| Packages     | `ReachyKit` (transport + domain) → `ReachyMedia` (WebRTC) / `ReachyScene` (RealityKit) → `ReachyUI` → `Apps/`       |

## Project Rules

1. **Upstream is a spec, not a source.** Read the Pollen repos to learn behavior; do not port their code.
2. **Safety lives in the daemon.** All robot commands go through the daemon API. Never duplicate or bypass motion
   limits, gravity compensation, or collision checks client-side.
3. **Version handshake first.** Read the daemon version on connect; unknown JSON fields must not break decoding.
4. **Robot identity ≠ IP.** Identify robots by stable identity (robot name / hardware id from the daemon), never by
   address (one robot can appear at several addresses — upstream issue #269).
5. **URLs via `URLComponents` only** — bare string interpolation breaks on IPv6 literals. Drop `fe80::` link-local
   addresses unless carrying a zone ID.
6. **Conventional commits** — enforced by the commit-msg hook.

## Detailed Rules

Consult `.claude/rules/` when working in the matching area:

| File                          | When to consult                          |
| ----------------------------- | ---------------------------------------- |
| `.claude/rules/daemon-api.md` | Endpoints, WebSockets, timeouts, jobs    |
| `.claude/rules/networking.md` | Discovery, ATS, Local Network permission |
