---
paths:
  - "Sources/ReachyKit/Transport/**"
  - "Apps/**"
---

# Discovery & local networking

## Discovery (lessons from upstream issue #269)

Upstream discovery loops forever when mDNS returns several addresses for one robot (IPv4 from different subnets,
link-local IPv6). Our rules:

- Identify a robot by `GET /api/daemon/hardware-id`, never by IP.
- Store the last successful address; manual IP entry is a first-class feature, not a fallback.
- Show the user which address is in use; provide a force-reconnect action.
- Build URLs with `URLComponents` (brackets IPv6 correctly). Drop `fe80::` link-local candidates unless carrying a
  zone ID.
- Connect must be idempotent and cancellable — no latching state machines.
- Static fallback host: `reachy-mini.local`. Upstream also probes `reachy-mini.home`; do NOT add it back. ATS waives
  its HTTPS requirement only for `.local` names, link-local addresses and single-label hosts, so a qualified `.home`
  name is always refused with `NSURLErrorDomain -1022` — confirmed on a running build. Loopback is probed as well on
  macOS and in the simulator, where a locally run `sim-daemon` advertises nothing the client can discover.
- Network change: `NWPathMonitor` + exponential backoff reconnect.

## iOS/iPadOS requirements (app targets)

- `NSLocalNetworkUsageDescription` + `NSBonjourServices` in Info.plist. Daemon mDNS service types (from upstream
  `src-tauri/src/discovery/mod.rs`): `_reachy-mini._tcp` (primary) and `_http._tcp` (legacy, filter instance names
  containing "reachy") — declare both.
- Local Network permission denial is SILENT: discovery returns an empty list, no error. UX must explain before the
  prompt, detect denial via timeout, and deep-link to Settings.
- ATS: `NSAppTransportSecurity → NSAllowsLocalNetworking: true` — allows plain HTTP to `.local`/link-local only. Never
  use blanket `NSExceptionDomains`.
- The daemon transport is plaintext and unauthenticated. Support only trusted private LANs or the robot AP; show this
  limitation in connection UI and never encourage public routing/port forwarding.

## Robot facts

- Wireless AP mode (out of box): SSID `reachy-mini-ap`, password `reachy-mini`, robot IP `10.42.0.1`.
- BLE Wi-Fi provisioning, daemon 1.9.0+. Upstream doc:
  `reachy_mini/src/reachy_mini/daemon/app/services/bluetooth/BLE_WIFI_PROVISIONING.md` (maps to CryptoKit X25519 +
  HKDF-SHA256 + AES-GCM). The authority is `bluetooth_service.py` beside it, not the doc — **the doc is wrong about
  replies.** It claims every command notifies, but `CommandCharacteristic.WriteValue` assigns the response value
  directly; only daemon-proxied commands notify, after an `OK: working` ack. So: write → read → await a notification
  only if the read was that ack. Awaiting unconditionally hangs on `PING`.
- The robot advertises the **status** service `…cdef3`, not the command service `…cdef0`, under the local name
  `ReachyMini` — identical on every unit, so robots are told apart only after connecting, by `…cdef7`.
- `WIFI_CONNECT_ENC` is ~260 B against iOS's default ATT MTU of 185, and the robot ignores write offsets. Budget every
  write with `maximumWriteValueLength(for: **.withoutResponse**)` — `ATT_MTU - 3`, the real single-packet capacity.
  `.withResponse` answers 512 on every iPhone: that is the maximum *attribute* length, reachable only because
  CoreBluetooth silently splits a longer value into ATT prepare/execute writes, which the robot then receives as
  separate commands. The command characteristic nevertheless accepts write-with-response only — the write type and
  the size budget are separate questions. Measure both on hardware before building on top of provisioning.
- CoreBluetooth reports a read result and a notification through the same `didUpdateValueFor` callback and offers no
  way to tell them apart. Harmless here: the robot sets the response characteristic's value either way, so a pending
  read may claim whichever arrives.
- `WIFI_SCAN` is truncated to 180 bytes (~8–15 SSIDs, no pagination), so manual SSID entry is mandatory, not a
  fallback. The PIN session dies on disconnect; the wrong-PIN lockout survives it.
