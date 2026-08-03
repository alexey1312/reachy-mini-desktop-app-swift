# Phase 0 — risk removal report

Goal: working skeleton + confirmation that no platform restriction blocks the project.

**Status: CLOSED 2026-08-03.** All risks resolved; no platform restriction blocks the project.

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
  `/api/state/ws/full`; `RobotConnection.handshake()` + `StateStreamClient` verified live (recorded here as 20 Hz —
  the daemon actually defaults to 10, corrected in phase 2)
  (`mise run test:sim`). Real WS frame recorded as test fixture (`full_state_recorded.json`). Two daemon realities
  the committed spec doesn't tell you: sim returns `{"hardware_id": null}` (identity falls back to robot name), and
  daemon payloads carry fields newer than the spec (tolerated by design).
- **WebRTC signaling (was part of phase 2 risk)** — port 8443 is plain `ws://` (no TLS), GStreamer `webrtcsink`
  signalling protocol confirmed live. See `webrtc.md`.

- **Spike app (`Apps/ReachySpike`)** — Tuist multiplatform target (iPhone/iPad/Mac) with the phase-0 Info.plist keys.
  Verified in the iOS Simulator against the sim daemon: `NWBrowser` finds `reachy_mini` via `_reachy-mini._tcp`
  (the daemon does advertise mDNS), handshake succeeds, state stream counts frames with a live Hz readout.
  Note: sim daemon v1.9.0 emits **10 Hz on the wire** (measured independently), not the documented 20 — the spike's
  rate counter is honest; re-measure on real hardware.

## On-device checks — passed on iPhone 17 Pro (iOS 26), 2026-08-03

- [x] Local Network permission prompt shows and is granted normally.
- [x] Bonjour discovery finds the daemon via `_reachy-mini._tcp`; both browsers `ready`.
- [x] Plain HTTP to a raw LAN IP passes; handshake returns daemon 1.9.0.
- [x] State stream runs at the daemon's wire rate (~10 Hz sim) with live counter.
- [ ] iPad — not tested (no device at hand); same binary, low risk.

Found by this run: entering `ip:port` in the host field tripped the IPv6-bracketing heuristic and produced a
bracketed pseudo-hostname that ATS rejected. Fixed with `RobotAddress(parsing:)` (host / host:port / [v6]:port /
bare IPv6), regression-tested.

## Remaining hardware checks

- **WebRTC on real hardware**: sim has no TLS on 8443 — re-verify on a physical Wireless robot.
- **Disconnect during motion**: daemon-side behavior still requires a physical safety test; server-side safety remains
  authoritative. Client behavior is covered by session cancellation and move-monitor tests.

O-3 and O-4 are closed by [ADR 0001](../adr/0001-daemon-compatibility-and-lan-security.md): daemon 1.9.0 is the pinned
minimum/tested baseline, compatibility is enforced during handshake, and v1 is explicitly limited to trusted private
LANs because the daemon has no authentication or encryption.
