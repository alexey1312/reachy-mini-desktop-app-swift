# Phase 0 — risk removal report

Goal: working skeleton + confirmation that no platform restriction blocks the project.

## Resolved

- **OpenAPI client generation** — works. The daemon spec (main branch of `pollen-robotics/reachy_mini`, 77 paths) uses
  Pydantic-style `anyOf: [X, {type: "null"}]` which swift-openapi-generator silently drops
  (apple/swift-openapi-generator#906/#817); `Scripts/normalize-openapi.py` strips the null branches during
  `mise run update-spec`. Generated types decode real payload shapes (see `Tests/ReachyKitTests`).
- **WebSocket state stream** — `StateStreamClient` connects to `/api/state/ws/full`, coalesces to consumer pace
  (`bufferingNewest(1)`), reconnects with exponential backoff. Verified by an in-process NWListener WebSocket server
  test that drops connections.
- **IPv6 addressing (upstream issue #269 class)** — Foundation's `URLComponents` rejects bare IPv6 literals in
  `host`; `RobotAddress` brackets them itself. Regression-tested.
- **mDNS service types (was O-1)** — `_reachy-mini._tcp` (primary) + `_http._tcp` (legacy, instance name contains
  "reachy"), from upstream `src-tauri/src/discovery/mod.rs`.
- **Simulator launch (was O-2)** — macOS needs `mjpython -m reachy_mini.daemon.app.main --sim`; `uv` has known MuJoCo
  issues on macOS → plain pip venv (`mise run sim-daemon`). `--fastapi-host 0.0.0.0` exposes it to LAN devices.

- **Simulated daemon end-to-end** — daemon v1.9.0 in MuJoCo sim answers REST (`/api/daemon/status`), streams
  `/api/state/ws/full` at 20 Hz; `RobotConnection.handshake()` + `StateStreamClient` verified live
  (`mise run test:sim`). Real WS frame recorded as test fixture (`full_state_recorded.json`). Two daemon realities
  the committed spec doesn't tell you: sim returns `{"hardware_id": null}` (identity falls back to robot name), and
  daemon payloads carry fields newer than the spec (tolerated by design).
- **WebRTC signaling (was part of phase 2 risk)** — port 8443 is plain `ws://` (no TLS), GStreamer `webrtcsink`
  signalling protocol confirmed live. See `webrtc.md`.

## Pending on-device checks (need the Tuist app shell)

- [ ] Local Network permission prompt shows; denial detected via discovery timeout; Settings deep link works.
- [ ] `NSAllowsLocalNetworking` passes plain HTTP to raw IPs and `.local` names without ATS errors.
- [ ] `NWBrowser` finds the simulated daemon (`_reachy-mini._tcp` / `_http._tcp`); `.local` resolution works.
- [ ] 20 Hz stream stable on iPhone + iPad for ≥ 5 min; reconnect after Wi-Fi switch.

## Open questions

- **O-3**: daemon has no authentication — anyone on the LAN can command the robot. Documented; product decision
  needed before public release.
- **O-4**: Pollen's API stability guarantees; robot behavior when a client disconnects mid-app.
- **WebRTC on real hardware**: sim has no TLS on 8443 — re-verify on a physical Wireless robot.
