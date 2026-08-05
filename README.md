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
- **Camera is WebRTC-only.** The daemon exposes no MJPEG endpoint, so video and two-way audio go through WebRTC.

## Architecture

| Layer         | What                                                                                                                               |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `ReachyKit`   | SPM package: generated OpenAPI client, WebSocket state stream, discovery, URDF and kinematics. Swift 6, strict concurrency, no UI. |
| `ReachyMedia` | WebRTC camera and two-way audio session, plus its video view.                                                                      |
| `ReachyScene` | RealityKit scene built from the robot's own URDF and meshes.                                                                       |
| `ReachyUI`    | Shared SwiftUI views.                                                                                                              |
| `Apps/`       | Thin per-platform shells, generated with Tuist.                                                                                    |

## Using the packages

All four layers are public SPM products (`ReachyKit`, `ReachyMedia`, `ReachyScene`, `ReachyUI`), so another app can
depend on them directly. `ReachyKit` is the only one that pulls in no UI framework.

```swift
.package(url: "https://github.com/alexey1312/reachy-mini-swift.git", branch: "main"),
```

There are no tagged releases yet, so pin a revision if you need a stable API. Minimum platforms are macOS 15 and
iOS 18 — `RealityView` in the 3D viewer sets that floor.

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

The daemon supports a MuJoCo simulation mode. `./bin/mise run sim-daemon` creates a project-local environment from
`Scripts/sim-requirements.txt`; the tested daemon baseline is pinned to **1.9.0**. Point the app (or an iPhone on the
same trusted network) at the Mac. The daemon's OpenAPI spec is committed at `Sources/ReachyKit/openapi.json` and
refreshed with `./bin/mise run update-spec`.

## Compatibility and network security

Daemon 1.9.0 is the minimum tested version. Newer 1.x daemons connect with a compatibility warning; older or
different-major versions are rejected before commands are sent. See
[ADR 0001](docs/adr/0001-daemon-compatibility-and-lan-security.md) for the policy.

The daemon provides **no authentication or encryption**. Use this client only on a trusted private LAN or the robot's
own access point. Never expose daemon port 8000 through port forwarding or a public address.

Reaching a robot from outside its network does **not** change that. It goes through the Hugging Face relay, which
brokers a WebRTC session between two peers that have both authenticated with the same account; the daemon's HTTP port
is never exposed, and commands travel on the session's data channel instead. See
[ADR 0003](docs/adr/0003-remote-access-over-the-hugging-face-relay.md).

## Status

Phase 2. Connection, discovery and network resilience are in place, along with live teleop, recorded moves, the daemon
log console, the WebRTC camera with two-way audio, and a 3D viewer that mirrors the robot from its own URDF.

The robot's app store installs and removes apps from Hugging Face Spaces, following each job over the daemon's job
socket. Signing in to Hugging Face — a public OAuth client with PKCE, the token in the Keychain — reaches private
Spaces, links a robot to the account, and lists the robots that account can reach from anywhere.

Still open in this phase: the Stewart platform's passive joints are computed client-side for the 3D view (the daemon
only reports them under the Placo kinematics engine), and BLE Wi-Fi provisioning. A remote session carries commands
and the camera but not the 3D scene, whose URDF and STL are HTTP-only.

## License

[Apache 2.0](LICENSE). [NOTICE](NOTICE) carries the attribution, the non-affiliation statement and the third-party
notices for the bundled dependencies (Apple's swift-openapi packages, Apache 2.0; Google WebRTC, BSD 3-Clause).
"Reachy Mini" is a product name of Pollen Robotics, used here solely to describe compatibility.
