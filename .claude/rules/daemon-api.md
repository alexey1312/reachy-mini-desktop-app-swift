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
  - `/api/state/ws/full` — full robot state (primary; take everything from here, REST `state/*` is fallback).
    Accepts query parameters that the spec cannot show. Defaults, read off `routers/state.py`:
    `frequency=10.0` (NOT 20 — and since the handler sleeps *after* building each frame, the real rate is a little
    lower), `with_head_pose=true`, `with_body_yaw=true`, `with_antenna_positions=true`, everything else false,
    including `with_head_joints` and `use_pose_matrix`. Modelled in `StateStreamOptions`.
    - **Never send `with_target_*`.** The frame builder asserts on them and the loop's blanket `except` swallows it,
      so the socket stays open and delivers nothing ever again. The only outward sign is a deduplicated
      `Skipping full-state frame:` line in the daemon journal. `StateStreamOptions` cannot express these on purpose.
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

- Daemon process ≠ robot backend. `/api/daemon/status` answers 200 with `backend_status: null` while the backend is
  torn down (`daemon.stop()` sets `self.backend = None`); every route behind the `get_backend` dependency
  (`move/*`, `state/*` incl. `ws/full`, `motors/*`, `kinematics/*`, `volume/*`) answers **503 "Backend not running"**.
  `camera/*` uses `get_daemon` instead, and `/logs/ws/daemon` is mounted at the app root — both outside that gate.
- Wake/sleep are multi-step protocols, not single calls: `motors/set_mode/enabled` → 300 ms → `move/play/wake_up`;
  sleep reverses it (animation first, `set_mode/disabled` only after it finishes). The play routes never touch the
  motor mode — an asleep robot accepts them, plays the sound, and does not move.
- `daemon/start?wake_up=<bool>` returns a job id immediately and starts the backend in the background (409 while
  another job runs); poll `daemon/status` until `running`. With `wake_up=true` the daemon enables the motors itself.
- No MJPEG endpoint exists. Camera is WebRTC-only (signaling `ws://<host>:8443`, GStreamer webrtcsink, single H.264
  Constrained Baseline 3.1 stream, Opus audio, STUN `stun.l.google.com:19302`).
- Daemon 1.9.0 is the minimum and tested API baseline. Enforce
  `DaemonCompatibilityPolicy` during the first status handshake: reject older/different-major versions, warn for
  newer 1.x or unknown versions, and tolerate unknown JSON fields. See `docs/adr/0001-daemon-compatibility-and-lan-security.md`.
- The daemon has no authentication or encryption. v1 supports trusted private LAN/robot AP only; never imply that a
  client-side token adds security and never expose port 8000 publicly.
- 9 actuators: `body_rotation`, `stewart_1..6`, `left_antenna`, `right_antenna`. Safety limits are clamped server-side.
- `passive_joints` in the state stream is `null` unless the daemon was launched with `--kinematics-engine Placo`; the
  default `AnalyticalKinematics` never computes them and there is no API to switch engines. The 21 Stewart passive
  joints are therefore worked out client-side, for 3D visualization only. Upstream's `kinematics-wasm` crate describes
  the behavior to reproduce — read it as a specification, never as code to port.
- URDF + STL meshes are served by the daemon: `GET /api/kinematics/urdf` (a `{"urdf": "<xml>"}` object, ~250 KB) and
  `GET /api/kinematics/stl/{filename}` (raw bytes as `model/stl` — its docstring claiming to return a *path* is
  stale). The generated client cannot fetch the STL: it declares `application/json` for every response.
- `GET /api/kinematics/info` reports only `{"info": {"engine", "collision check"}}` — no joint names, no limits. Those
  live in the URDF alone.
- DoA angle (microphone direction of arrival) is in radians: 0 = left, π/2 = front/back, π = right.
- Speaker and microphone levels are `GET|POST /api/volume/{current,set}` and `/api/volume/microphone/{current,set}`,
  both `{"volume": 0…100}` in and `{volume, platform, device}` out. There is no separate "sensitivity" concept —
  microphone sensitivity *is* its input level. Wrapped as `AudioLevel`.
  - **`POST /api/volume/set` plays a test sound on every accepted call** (it is in the route's own description).
    Send it once a slider gesture ends, never on each change, or the robot beeps continuously.
  - Out-of-range values come back as 422, so both setters map `.unprocessableContent` explicitly.
  - On `sim-daemon` these routes drive the **host Mac's own** speaker and mic (`platform: Darwin`), not a robot.
    Note the level before testing and restore it after.
