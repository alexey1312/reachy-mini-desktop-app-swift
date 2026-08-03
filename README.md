# ReachyMini for Swift

Native macOS / iPadOS / iOS client for the **Reachy Mini Wireless** robot by
[Pollen Robotics](https://www.pollen-robotics.com). Unofficial, not affiliated with Pollen Robotics.

This is **not a fork** of the official
[desktop app](https://github.com/pollen-robotics/reachy-mini-desktop-app) — it is an independent Swift client for the
robot daemon's documented HTTP/WebSocket API. The upstream repository is used as a behavioral specification, not as a
source of code.

## Why native

Things a web stack fundamentally can't do: ARKit face tracking mapped onto the robot's 6-DoF Stewart platform, Core
Haptics, Siri and App Intents, Live Activities, an Apple Watch remote, and a path to visionOS via RealityKit.

## Scope

- **Wireless only.** On the Wireless model the daemon runs on the robot itself (`http://reachy-mini.local:8000`), so
  this app is a pure network client. The Lite model (daemon on a USB-connected computer) is out of scope for v1 — a
  Lite owner can still connect if the daemon runs on a reachable host in the same network.
- **No camera in v1.** The daemon exposes camera video via WebRTC only (there is no MJPEG endpoint); WebRTC lands in
  phase 2 together with two-way audio.

## Architecture

| Layer       | What                                                                                                                                |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `ReachyKit` | SPM package: generated OpenAPI client, WebSocket state stream (20 Hz), discovery, domain model. Swift 6, strict concurrency, no UI. |
| `ReachyUI`  | Shared SwiftUI + RealityKit views (phase 1+).                                                                                       |
| `Apps/`     | Thin per-platform shells, generated with Tuist.                                                                                     |

## Getting started

```bash
./bootstrap.sh
```

That's it — one script installs all pinned tools via a self-contained [mise](https://mise.jdx.dev) binary (`bin/mise`)
and wires git hooks. Swift itself is managed by [swiftly](https://www.swift.org/swiftly/) via `.swift-version`.

```bash
./bin/mise run build        # build the Swift package
./bin/mise run test         # run tests
./bin/mise run sim-daemon   # run a simulated robot daemon (MuJoCo) for development without hardware
./bin/mise tasks            # list all tasks
```

## Development without hardware

The daemon supports a MuJoCo simulation mode. Run `./bin/mise run sim-daemon` on a Mac and point the app (or an iPhone
on the same network) at it. The daemon's OpenAPI spec is committed at `Sources/ReachyKit/openapi.json` and refreshed
with `./bin/mise run update-spec`.

## Status

Phase 0 — risk removal: generated API client, state stream from a simulated daemon, on-device validation of Local
Network permission and ATS local-networking rules.

## License

[Apache 2.0](LICENSE). See [NOTICE](NOTICE) for attribution. "Reachy Mini" is a product name of Pollen Robotics, used
here solely to describe compatibility.
