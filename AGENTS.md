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
  to tuist.dev (`alexey1312/reachy-mini-desktop-app-swift` in `Apps/Tuist.swift`). That handle names the **tuist.dev
  project**, not this repository, and deliberately keeps the pre-rename name: renaming the GitHub repo does not rename
  the server-side project, so "fixing" it to match `reachy-mini-swift` points generation at a project that does not exist.
- Run every `tuist` command from `Apps/` — `Tuist.swift` lives there and tuist only searches _upward_, so from the repo
  root it finds no manifest and reports the project as unconnected to the server (`run 'tuist init'`).
- Use `mise run inspect:bundle [path]` rather than `tuist inspect bundle`: it handles the cwd, defaults to the iOS
  device bundle, and rejects a macOS one (which keeps `Info.plist` under `Contents/`, where the command wants it at
  the root). Size numbers only mean something off a Release archive — a Debug bundle carries `__preview.dylib`,
  `*.debug.dylib` and the provisioning profile, none of which ship.
- Do **not** set `enableCaching` — without a running cache daemon every compile task waits out a CAS socket deadline,
  and CI has neither the daemon nor cache credentials (this repo is not connected to the tuist.dev project).

## Quick Reference

```bash
./bin/mise run build          # Debug build (piped through xcsift)
./bin/mise run build:app      # Build the ReachySpike app target (generates first)
./bin/mise run test           # All tests, parallel
./bin/mise run test:filter T  # Filter tests
./bin/mise run lint           # SwiftLint --strict + actionlint + hk lockstep
./bin/mise run format         # Format all (hk fix --all)
./bin/mise run format-check   # CI formatting check
./bin/mise run project        # tuist generate (Apps/)
./bin/mise run inspect:bundle # Upload an iOS bundle-size analysis to tuist.dev
./bin/mise run sim-daemon     # Simulated robot daemon (MuJoCo, LAN-reachable)
./bin/mise run update-spec    # Refresh + normalize daemon OpenAPI spec
```

`build` / `test` are SwiftPM only — they never compile `Apps/ReachySpike`. Use `build:app` for that; CI runs it as a
separate job, so app-target breakage no longer reaches `main` unnoticed.
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
