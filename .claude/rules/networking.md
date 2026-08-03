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
- Static fallback hosts upstream probes: `reachy-mini.local`, `reachy-mini.home`.
- Network change: `NWPathMonitor` + exponential backoff reconnect.

## iOS/iPadOS requirements (app targets)

- `NSLocalNetworkUsageDescription` + `NSBonjourServices` in Info.plist. Daemon mDNS service types (from upstream
  `src-tauri/src/discovery/mod.rs`): `_reachy-mini._tcp` (primary) and `_http._tcp` (legacy, filter instance names
  containing "reachy") — declare both.
- Local Network permission denial is SILENT: discovery returns an empty list, no error. UX must explain before the
  prompt, detect denial via timeout, and deep-link to Settings.
- ATS: `NSAppTransportSecurity → NSAllowsLocalNetworking: true` — allows plain HTTP to `.local`/link-local only. Never
  use blanket `NSExceptionDomains`.

## Robot facts

- Wireless AP mode (out of box): SSID `reachy-mini-ap`, password `reachy-mini`, robot IP `10.42.0.1`.
- BLE Wi-Fi provisioning protocol is documented upstream:
  `reachy_mini/src/reachy_mini/daemon/app/services/bluetooth/BLE_WIFI_PROVISIONING.md` (phase 2; maps to CryptoKit
  X25519 + HKDF-SHA256 + AES-GCM).
