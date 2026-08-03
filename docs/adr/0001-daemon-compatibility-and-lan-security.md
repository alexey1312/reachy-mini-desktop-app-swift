# ADR 0001: Daemon compatibility and LAN security

- Status: Accepted
- Date: 2026-08-03

## Context

The daemon updates independently, its OpenAPI document has no stability guarantee, and its hand-written WebSockets
are outside that document. Daemon 1.9.0 is the version verified against the simulator and recorded state fixture.
The daemon exposes motion commands over plaintext HTTP/WebSocket and has no authentication API.

## Decision: compatibility

- Daemon 1.9.0 is both the minimum supported and tested baseline for this client.
- Handshake reads status/version before identity or any robot command.
- A parseable 1.x version below 1.9.0, or any different major version, is rejected with an actionable error.
- A newer 1.x version is allowed with a persistent compatibility warning. Unknown JSON fields remain tolerated.
- A missing or malformed version is allowed in limited/unknown mode with a warning, because older deployments may
  omit metadata even when their endpoint shape works.
- Optional endpoint failure disables that feature; it must not invalidate an otherwise healthy session.
- `Scripts/sim-requirements.txt` pins the simulator baseline. Updating it requires updating the policy, fixture and
  compatibility tests together after a live simulator check.

## Decision: security

Version 1 supports only a trusted private LAN or the robot's own access point. The UI states that transport is
unauthenticated and unencrypted. Users must not expose port 8000 through port forwarding, a public IP, or an
untrusted network. Client-side tokens or a fake pairing screen are explicitly rejected: without daemon support they
provide no security.

Authenticated remote access is a release blocker, not a client-only follow-up. It requires an upstream daemon
protocol for pairing, authenticated HTTP/WebSocket requests and transport encryption. Credentials must then live in
Keychain and be injected centrally by ReachyKit.

## Consequences

Anyone with network access to the daemon can command the robot. Server-side motion limits remain the safety boundary.
The compatibility warning is informative for newer/unknown daemons; unsupported versions fail before commands.
