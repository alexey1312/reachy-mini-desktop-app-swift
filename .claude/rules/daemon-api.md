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
- **The committed spec describes a daemon newer than 1.9.0, so a generated call can 404 on a supported robot.** `main`
  is where it comes from, and 1.9.0 is the baseline we accept — the generator cannot know the difference, and neither
  can the version string (a newer daemon still reports `1.9.0` until it is bumped). Five routes are in the spec and
  absent from 1.9.0: `daemon/robot-name` (both verbs), `apps/start-app/{app}/no-evict`, and the three
  `hf-auth/oauth/device/*`. Diff against the robot itself (`curl http://<host>:8000/openapi.json`) before building a
  screen on a route, and gate the feature on a probe rather than on the version — `RobotConnection.handshake` reads
  `robot-name` for the display name and takes its 404 as `supportsRename = false`.
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

## Wireless-only routes

- `/wifi/*` and `/update/*` mount at the app ROOT (no `/api`) and only under `--wireless-version`. The committed spec
  is generated without that flag, so they are absent from it and the generated client cannot reach them — hand-write
  them. A Lite robot 404s; gate on `DaemonStatus.wireless_version`.
- `/update/ws/logs` sends each line as a text frame AND then a `JobInfo` JSON frame repeating those same lines —
  decode JSON first and ignore its `logs`, or every line doubles. The job ends with `systemctl restart`, which kills
  the daemon before a terminal `done`: the socket closing is completion, confirmed by reconnecting and comparing
  versions. `available_version: "unknown"` means the ROBOT could not reach PyPI, not that the check failed.
- The daemon's own source is installed at `.venv-sim/lib/python3.12/site-packages/reachy_mini/` — read
  `daemon/app/routers/*.py` and `daemon/app/services/bluetooth/` there rather than guessing a shape. It is a
  specification (project rule 1), never code to port.
- `/wifi/*` routes, from `routers/wifi_config.py`: `GET /wifi/prov_key`, **`POST`** `/wifi/scan_and_list` (a POST
  because it rescans first; uncapped, unlike the 180-byte BLE reply), `POST /wifi/connect_sealed`,
  `GET /wifi/status`, `GET /wifi/error`, `POST /wifi/reset_error`, `POST /wifi/forget?ssid=`, `POST /wifi/forget_all`.
  Plaintext `POST /wifi/connect?ssid=&password=` exists and must never be called — the PSK would go in a query string.
- `connect_sealed` answers `400 decrypt_failed` for a wrong PIN **and** for a `kid` older than the 600 s rotation, and
  409 while another `nmcli` operation runs. It returns immediately and joins on a background thread; on failure it
  removes the connection and re-raises its own hotspot, so the reason ends up in `GET /wifi/error`, not in the reply.
- `GET /wifi/status` is `{mode: hotspot|wlan|disconnected|busy, known_networks, connected_network}` — a joined station
  is `wlan`, not `connected`, and there is **no IP address in it**. The BLE status characteristic is the mirror image:
  live address, no network names. Neither contains the other.
- `POST /wifi/forget` answers 404 for a network the robot never saved and 400 for `Hotspot`. Everywhere else in
  `/wifi/*` and `/update/*` a 404 means the route was never mounted, i.e. a Lite robot.
- `GET /api/daemon/hardware-id` answers one key, `{"hardware_id": "<16 hex>"}` = `sha256(usb serial)[:16]` — the same
  string as mDNS TXT `unit_id` and BLE characteristic `…cdef7`. It is a join key: never reshape it.

## Hugging Face on the robot (`/api/hf-auth/*`)

The robot's **own** account, which is not this app's — read `daemon/app/routers/hf_auth.py` and
`apps/sources/hf_auth.py` in `.venv-sim`. Linking hands the robot a copy of a token so it can register with central;
this app keeps its own in the Keychain (ADR 0003).

- `POST /save-token`, `DELETE /token`, `GET /status` → `{is_logged_in, username}`.
- `GET /relay-status` → `{state, message, is_connected}`. A Lite robot answers `state: "unavailable"` with
  "Coming soon to Lite version" — a state the relay's own enum does not contain, so decode it tolerantly.
- `POST /refresh-relay`, `GET /central-robot-status`.
- **No route ever returns the token.** `/status` answers a boolean and a username; the OAuth flow below answers a
  status and a username. Delegating sign-in to the robot therefore cannot give this app a token of its own — that was
  checked before building on it.
- OAuth on the robot: `GET /oauth/configured|start|begin|status/{session_id}|callback`, `DELETE /oauth/session/{id}`.
  `start` returns `{auth_url, session_id}` to poll; `begin` 302s straight to Hugging Face for a phone that can only
  open one URL. The default client id is Pollen's own (`71146982-…`, `HF_OAUTH_CLIENT_ID` to override) and its
  redirects point at the **robot** (`http://reachy-mini.local:8000/api/hf-auth/oauth/callback`, or localhost for Lite),
  so it cannot be reused by a client with a custom scheme.
- Daemon 1.9.0 does not mount `hf-auth/oauth/device/*` even though the committed spec has it (see the spec-ahead-of-
  firmware trap above).

## Bluetooth service

Read `services/bluetooth/bluetooth_service.py` in `.venv-sim` — the dispatch table is one `if/elif` chain and settles
most questions in a glance.

- It is **its own systemd unit** (`reachy-mini-bluetooth`, working directory `/bluetooth`), not part of the daemon.
  Every recovery script ends with `systemctl restart reachy-mini-daemon`, so the Bluetooth link survives all of them —
  including `SOFTWARE_RESET`, which erases `/venvs` while the service sits outside it. `PING` therefore proves the
  robot is there, never that a reset finished.
- The commands are exactly `PING`, `STATUS`, `JOURNAL_{START,READ,STOP}`, `PIN_*`, `UPDATE_{CHECK,START,INFO}`,
  `WIFI_{KEYEX,STATUS,SCAN,CONNECT_ENC,FORGET}`, `CMD_*`. Anything else falls through to `ECHO:`. **There is no
  `SET_NAME`** — renaming is `POST /api/daemon/robot-name`, which 1.9.0 does not mount either, so such a robot cannot
  be renamed at all: its name is whatever `--robot-name` the daemon was started with (default `reachy_mini`).
- The PIN is the last five characters of the Pollen audio device's USB serial (`38fb:1001`, read from
  `/sys/bus/usb/devices/*/serial`), compared verbatim: not necessarily digits, never case-folded. Do not uppercase the
  input field. Upstream states that serial is printed on the robot — it is **not** a separate code, and no route
  exposes it, which is the point. With no audio board attached the daemon falls back to a fixed `46879`.
- `CMD_*` clears the robot's own auth flag in a `finally`, so the PIN is needed again after every script — whether it
  succeeded or not. Its handler also returns `None` on success, so the reply encoder crashes and the GATT write
  reports an error for a script that ran perfectly.
- `_read_journal` returns `buffer[:480]` and **deletes what it returned**. One BLE read carries ~182 bytes, so the
  remainder of every large chunk is lost for good, and a line is regularly cut in half — `BLEJournalReader` carries the
  tail. The LAN journal is the authoritative one; say so in any UI that shows this.
  - The journal is a byte stream, not a message, so `BLEResponseParser` returns `.payload` **verbatim**. Trimming it
    (as every other reply is trimmed) eats the trailing newline that says the last line is complete, and the reader
    then glues that line onto the next chunk — one corrupted line per read boundary, which looks like nothing at all
    when a chunk holds a single line.
  - `journalctl` exits on its own; the GLib watch removes itself on HUP and every later read answers
    `ERROR: Journal not running`. That is a `JOURNAL_START` away from fixed, not a terminal state.
- `…cdef6` is `", ".join(...)` over the robot's `commands/` directory with `.sh` stripped, `"None"` when empty, in
  `os.listdir` order. Read it; never hardcode the list, and sort it before showing it.

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
