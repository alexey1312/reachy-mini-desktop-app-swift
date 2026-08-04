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
- `BLECommand` is the whole set the robot answers — anything else comes back as `ECHO:`. Renaming is **not** in it:
  daemon 1.9.0's dispatch has no `SET_NAME` branch, so a rename only works over HTTP.
