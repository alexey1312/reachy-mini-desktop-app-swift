# Known robots in the connection list

## Problem

`ConnectionScreen` builds "Robots on this network" from live Bonjour results alone. A robot the app has just
been connected to — whose address it stored, whose name and hardware id it read during the handshake — never
appears there. When mDNS does not reach the device (guest networks, routers that filter multicast, a robot
that dropped off the air), the section shows "Searching…" indefinitely while the Manual address field below
displays a perfectly good address, which reads as "the app knows the robot but refuses to list it".

Observed on device: after Disconnect the list stayed empty; the robot was in fact off the network (no HTTP,
no ping, ARP incomplete). The screen had no way to say so, because it only ever renders what Bonjour returns.

## Goals

- A robot that was connected to before stays listed, with its name, whether or not Bonjour finds it.
- The list distinguishes "on the network" from "not responding", so an absent robot is visible as absent.
- Reconnecting after Disconnect is one tap.
- A robot can be forgotten.

Not in scope: changing discovery itself, automatic reconnect policy, or the Manual address flow.

## Design

### Storage — `KnownRobots` (ReachyKit)

```swift
public struct KnownRobot: Codable, Hashable, Sendable, Identifiable {
    public let key: String        // RobotIdentity.deduplicationKey
    public var name: String?
    public var address: RobotAddress
    public var lastConnected: Date
}
```

`key` is `RobotIdentity.deduplicationKey` — the hardware id, falling back to the robot name when the daemon
reports none (the simulator does exactly that). Records live in `UserDefaults` as JSON under
`ReachyKit.knownRobots`, newest first.

- `KnownRobots.all` — the stored records, sorted by `lastConnected` descending.
- `KnownRobots.remember(identity:address:at:)` — upsert by `key`; refreshes name, address and timestamp, so a
  robot that moved to a new address updates in place rather than duplicating (project rule 4).
- `KnownRobots.forget(_ key:)` — drops one record, and clears `lastAddress` when it pointed at that robot.

`lastAddress` stays as it is. The Manual address field and the auto-connect candidate sweep both read it, and
neither wants the identity-keyed record.

`RobotSession.connect` writes the record where it already writes `lastAddress`, right after a successful
handshake — the one place that holds both the identity and the address.

### Identity in discovery — TXT records

`RobotBrowser` moves from `.bonjour(type:domain:)` to `.bonjourWithTXTRecord(type:domain:)`, and
`DiscoveredService` gains `hardwareID: String?` read from the TXT key `unit_id`. The daemon publishes it
(confirmed against hardware: `unit_id=b68ff6bbe47f0608`), and it is the same string as
`GET /api/daemon/hardware-id` — the join key the daemon-api rules call out. Legacy `_http._tcp` adverts may
carry no TXT at all, so the field is optional and a `nil` simply never matches a stored record.

### Reachability — `RobotReachability` (ReachyKit)

`probe(address:timeout:)` issues a short `GET /api/daemon/hardware-id` built with `URLComponents` (rule 5) and
reports reachable / not. It deliberately does not handshake: this runs every 10 s per known robot and only has
to answer "is anything serving the daemon API there".

### Screen model — `KnownRobotsModel` (ReachyUI)

`@MainActor @Observable`, beside the view as `Sources/ReachyUI/AGENTS.md` requires. Holds the records with a
per-record status (`checking`, `reachable`, `unreachable`), re-probes every 10 s while the screen is on
screen, and exposes `forget(_:)`. The probe is injected, so tests never touch the network and previews stay
inert.

### UI — `ConnectionScreen`

Inside "Robots on this network":

- Known robots render as rows: name (address when unnamed), with the status on the trailing edge.
- A Bonjour result whose `hardwareID` matches a known record is folded into that record's row rather than
  listed twice; an unmatched result keeps rendering as it does today.
- Tapping a row connects — the same manual path as the Connect button, so it clears the Disconnect pause.
- Swipe deletes a record.
- "Searching…" now appears only when there is nothing at all to show: no Bonjour results and no known robots.
- The "Forget last robot" button goes away; the swipe replaces it.

## Testing

- `ReachyKitTests`: upsert by identity (same robot at a new address updates in place), ordering, forgetting,
  and `lastAddress` cleanup; `unit_id` extraction from a TXT record; `RobotReachability` against
  `StubURLProtocol` for 200, 500 and a refused connection.
- `ReachyUITests`: `KnownRobotsModel` status transitions driven by an injected probe, polling the condition
  rather than sleeping (project rule 7), and `forget`.
- Previews for the new states — known robot not responding, known robot on the network, known plus an
  unmatched Bonjour result — with recorded snapshots (project rule 8).
