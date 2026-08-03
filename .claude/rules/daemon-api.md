---
paths:
  - "Sources/ReachyKit/**"
---

# Daemon API knowledge

Base: `http://<host>:8000/api`. Port is configurable in our client (upstream hardcodes 8000).

## Spec

- REST: OpenAPI 3.1 at `Sources/ReachyKit/openapi.json`; canonical source
  `https://raw.githubusercontent.com/pollen-robotics/reachy_mini/main/docs/source/API/openapi.json` (main is ahead of
  develop there). Refresh with `./bin/mise run update-spec` — it also normalizes `anyOf: [X, {type: null}]` branches
  that swift-openapi-generator silently drops (`Scripts/normalize-openapi.py`). Swagger UI at `http://<host>:8000/docs`
  when a daemon runs.
- WebSockets are NOT in the spec (FastAPI omits them). Known endpoints (from
  `reachy_mini/src/reachy_mini/daemon/app/routers/`):
  - `/api/state/ws/full` — full robot state at 20 Hz (primary; take everything from here, REST `state/*` is fallback)
  - `/api/move/ws/set_target` — live teleop
  - `/api/move/ws/updates`, `/api/move/ws/raw/write`
  - `/logs/ws/daemon` — daemon journal (NOTE: mounted at app root, not under `/api`, and ONLY with
    `--wireless-version` — absent on the simulator, upgrade rejected with 403)
  - `/api/apps/ws/apps-manager/{job_id}` — install/remove job stream (prefer over polling `job-status`)

## MVP endpoint subset (what upstream actually calls)

`daemon/status|start|stop`, `daemon/hardware-id`, `daemon/robot-name`, `state/full`, `move/set_target`,
`move/play/wake_up`, `move/play/goto_sleep`, `move/play/recorded-move-dataset/{dataset}/{move}`,
`move/recorded-move-datasets/list/{dataset}`, `motors/set_mode/{mode}`, `apps/job-status/{id}`, `kinematics/info`.

## Timeouts (from upstream `src/config/daemon.ts` — battle-tested values)

- Healthcheck request timeout: 2 s (3.5 s over Wi-Fi); status poll every 3 s (5 s Wi-Fi).
- Connected-state hysteresis: require 2 consecutive successful probes to go "connected"; downgrade immediately on
  failure.
- Job polling: 500 ms; app install timeout 60 s, remove 90 s, start 120 s; stale-job 90 s.

## Facts

- No MJPEG endpoint exists. Camera is WebRTC-only (signaling `ws://<host>:8443`, GStreamer webrtcsink, single H.264
  Constrained Baseline 3.1 stream, Opus audio, STUN `stun.l.google.com:19302`).
- Daemon has NO authentication (open question O-3) — anyone on the LAN can command the robot.
- 9 actuators: `body_rotation`, `stewart_1..6`, `left_antenna`, `right_antenna`. Safety limits are clamped server-side.
- `passive_joints` in the state stream is `null` with the default kinematics engine; the 21 Stewart passive joints are
  computed client-side only for 3D visualization (phase 2, Swift port of upstream `kinematics-wasm` crate).
- URDF + STL meshes are served by the daemon: `GET /api/kinematics/urdf`, `GET /api/kinematics/stl/{filename}`.
- DoA angle (microphone direction of arrival) is in radians: 0 = left, π/2 = front/back, π = right.
