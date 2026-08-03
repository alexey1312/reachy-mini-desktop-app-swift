# WebRTC signaling research (Phase 0 spike)

Probed against the simulated daemon v1.9.0 (`mise run sim-daemon`), 2026-08-03.

## Findings

- Port 8443 speaks **plain `ws://` — no TLS at all** (HTTPS probe fails, raw WebSocket connects). The
  "self-signed certificate on iOS" concern from the brief is moot, at least for the sim: nothing to pin or trust.
  Re-verify on real Wireless hardware.
- Protocol is the **GStreamer `gst-plugins-rs` webrtc signalling protocol** (same one `webrtcsink` ships):
  - on connect the server sends `{"type": "welcome", "peerId": "<uuid>"}`
  - `{"type": "list"}` → `{"type": "list", "producers": [...]}`
  - `{"type": "setPeerStatus", "roles": ["listener"], "meta": {}}` → `peerStatusChanged`
  - session flow (from the gst protocol, to verify live): `startSession` → `sessionDescription` (SDP offer/answer) →
    `ice` candidates → `endSession`
- `producers` is empty in the sim until media is acquired (`POST /api/media/acquire`; camera specs name is `mujoco`).
- Upstream client reference: `src/hooks/media/useWebRTCStream.ts` (STUN `stun.l.google.com:19302`, single H.264
  Constrained Baseline 3.1 stream + Opus).

## Phase 2 implications

- The signaling client is a trivial JSON-over-WebSocket state machine — no third-party dependency needed for it.
- The heavy decision remains the RTC stack itself (WebRTC.framework binary vs alternatives); H.264 CBP 3.1 + Opus are
  well inside WebRTC.framework's defaults.
- No TLS handling needed if hardware matches the sim; check the Wireless robot before assuming.

## Phase 2 verification (2026-08-03, sim daemon v1.9.0)

Implemented in `ReachyKit` (`SignalingMessage`, `CameraSignalingClient`) + `ReachyMedia` (`CameraSession`,
stasel/WebRTC binary xcframework). Verified live against the sim:

- Full session flow confirmed exactly as speced: `welcome` → `setPeerStatus(listener)` → `peerStatusChanged` →
  `list` → `startSession` → `sessionStarted` → `peer{sdp offer}` (robot is the offerer) → `peer{ice}` both ways →
  `endSession`. Error messages use `{"type": "error", "details": ...}`.
- The sim's producer registers as `meta.name == "reachymini"` (not `mujoco` — that's only the camera specs name).
- Gotcha: without `GST_PLUGIN_SCANNER` pointing into the venv, GStreamer's plugin loader fails silently, webrtcsink
  can't discover the Opus encoder ("No caps found for stream audio_0") and **no producer ever appears on :8443**
  while `/api/media/status` still reports `available: true`. `mise run sim-daemon` now sets it.
- Sim-gated test: `SimulatorIntegrationTests/webrtcSignaling` negotiates to a real SDP offer via `mise run test:sim`.
