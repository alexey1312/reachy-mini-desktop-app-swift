# ReachyKit

Transport + domain core. No UI imports (SwiftUI/UIKit forbidden here). Swift 6 strict concurrency.

- `openapi.json` + `openapi-generator-config.yaml` → client generated at build time by the OpenAPIGenerator plugin
  (types + client, idiomatic naming). Refresh spec: `./bin/mise run update-spec` (fetches + normalizes null-type
  anyOf branches the generator can't handle — see `Scripts/normalize-openapi.py`).
- Pydantic `Optional[X]` without a default is _required and nullable_; the normalizer must also drop such properties
  from `required`, or the generated Swift field is non-Optional and a real null throws (`DaemonStatus.backend_status`).
- WebSocket endpoints are hand-written (not in the spec) — see `Transport/`.
- Unknown JSON fields must never break decoding (daemon updates independently of this app).
- `RobotAPIClient` supplies throwing defaults for everything except `handshake`, `daemonStatus`, `wakeUp` and
  `gotoSleep` — every test double must implement those four. `/wifi/*` and `/update/*` live on separate protocols so
  doubles for the connection surface stay small.
- Bluetooth layers as `BLETransport` (CoreBluetooth behind a seam; `FakeBLETransport` is the only stand-in, since the
  robot's GATT service is Linux/BlueZ) → `BLECommandPump` (one command at a time, write→read→maybe-notify) →
  `BLELink` (`@MainActor @Observable`, the screens' state). One link per transport: the response characteristic
  carries no correlation id, so a second pump on the same transport would race the first for its replies. Provisioning
  and recovery are therefore two halves of `BLELink`, not two session types (`BLELink+Recovery.swift`).
- Provisioning is written against `WiFiProvisioningTransport`, not against BLE: `BLEProvisioningTransport` and
  `RobotConnection` both implement it, so the sealing and the screens are shared and the HTTP path is available if the
  ~260-byte sealed payload turns out not to fit one ATT write. `WiFiConfigClient` adds the settings-only routes.
- `RemoteDataChannel` is the seam under a remote session, and the **end of `messages()` is terminal**:
  `RemoteControlChannel` reads it as "the session is over" and fails every waiter with `.closed`. A peer being
  replaced must therefore not end it — every WebRTC negotiation replaces the peer, the _first offer included_, so
  conflating the two broke remote control on the very first handshake and left the reader deaf for good (it now
  re-subscribes, `endReading`). `WebRTCDataChannel` splits the two: `detachPeer()` is a gap (sends go back to
  waiting, the stream lives), `close()` is an ending. `isOpen` exists for the same distinction one layer up — a
  command issued while the channel is between peers is timing a negotiation, not a robot, and gets `openingTimeout`
  (30 s) rather than the reply budget (10 s). Ask it afresh; the opening wait comes back after every ICE failure.
- A bare `Error` enum reaches the UI as `<Module>.<Type> error <n>`, where `n` is the case's **declaration index**:
  `RemoteControlChannel.Failure error 2` is `.closed`, the third case. None of these enums carry `LocalizedError`, so
  counting cases is how a screenshot names a root cause.
- `BLECommand` is the whole set the robot answers — anything else comes back as `ECHO:`. Renaming is **not** in it:
  daemon 1.9.0's dispatch has no `SET_NAME` branch, and it does not mount `POST /api/daemon/robot-name` either — that
  route postdates the release, so on 1.9.0 a robot cannot be renamed at all. `handshake` probes the route and reports
  `supportsRename`; the field is greyed out rather than left to 404 on save.
