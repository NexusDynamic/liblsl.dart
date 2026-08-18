# peer_coordinator chat

A small multi-device chat app built on
[`peer_coordinator`](../README.md). It exists to show the coordination model at
work: several nodes join a named room, elect a coordinator between themselves,
keep a live roster by heartbeat, and exchange messages — all without a server
that knows anything about the application.

Runs on macOS, iOS, Android, Linux, Windows and the web.

## Running it

**1. Start a hub.** The WebSocket transport relays through one hub process,
which ships with the package:

```sh
cd packages/peer_coordinator
dart run peer_coordinator:hub --generate-secret          # once, note it down
dart run peer_coordinator:hub --session lounge-session --secret '<that secret>'
```

The hub is role-blind — it forwards frames and tracks who is connected, and
knows nothing about election, membership or streams. What it does enforce is
entry: every peer proves knowledge of the shared secret before the hub honours
a single frame, so the session name and secret go in the app's connect form
alongside the hub URL.

`--secret` is fine on your own machine but is visible in the process list; use
`--secret-file` or the `HUB_SECRET` environment variable anywhere else.

**Reaching it from another device.** The hub binds loopback by default. On a
trusted LAN, `--host 0.0.0.0` is enough to let phones reach it. Over the
internet, do not expose the hub's port — it speaks `ws://`, not `wss://`. Put
it behind the reverse proxy in [`../deploy/`](../deploy/README.md) and connect
to `wss://your-domain`, which is two commands and gets you a real certificate.

**2. Start the app**, once per participant:

```sh
cd packages/peer_coordinator/example
flutter run -d macos      # and again with -d chrome, or on a device
```

Enter a display name, the hub URL (`ws://127.0.0.1:8080` on the same machine,
`ws://<hub-machine-ip>:8080` from a phone) and a room name. Everyone using the
same room name lands in the same session.

The first node to join finds no one to defer to and becomes the **coordinator** —
the app bar says which role this node holds.

## Relay or direct

The connect screen offers two transports, and `ChatSession` cannot tell which
one it got — it takes an `ITransportConfig` and never asks. Switching medium
changes exactly one expression in the whole app, `_transportConfig` in
[`lib/src/ui/connect_page.dart`](lib/src/ui/connect_page.dart).

| | Relay | Direct |
| --- | --- | --- |
| carries the data | the hub | a WebRTC data channel, peer to peer |
| hops | two | one |
| the hub still does | everything | discovery and signalling only |

Both need the hub running. Two peers that have never met cannot exchange a
WebRTC offer over the connection the offer is for, so direct mode uses the same
socket to carry the offers, answers and candidates — it just stops sending it
the messages.

### STUN, and why the field is empty by default

Direct mode has a **STUN servers** field. Leave it empty on a LAN: with no ICE
servers the peers gather host candidates only, so the connection involves no
third party whatsoever, which is what this mode is for.

Across the internet, two peers behind NATs cannot learn their own public
addresses on their own, and empty means they never connect. A STUN server tells
each peer what its address looks like from outside and then takes no further
part — the data still goes peer to peer. The globe button fills in a public one;
a comma or space separated list works too.

**TURN is refused, deliberately.** A TURN-relayed connection sends the bytes
through someone else's server, so it is peer-to-peer in name only and the halved
hop count direct mode exists for does not survive it. If you want a relay, Relay
mode is the honest way to have one.

## How a message actually travels

The user-message channel is shaped by the coordination topology, not by a mesh:

| Sender | Reaches |
| --- | --- |
| coordinator `sendUserMessage` | every participant, as `UserCoordinationEvent` |
| participant `sendUserMessage` | **only the coordinator**, as `UserParticipantEvent` |

So a chat needs the coordinator to relay: when it receives a participant's line
it re-broadcasts the payload verbatim, which is what keeps the original
author's name on the message instead of the relay's. That is `_relay` in
[`lib/src/chat/chat_session.dart`](lib/src/chat/chat_session.dart), and
[`test/chat_relay_test.dart`](test/chat_relay_test.dart) is the proof — it runs
three whole sessions over the in-memory transport, no hub and no sockets:

```sh
flutter test
```

A consequence of relaying is that a line can reach a node twice — most obviously
the coordinator, which subscribes to its own coordination stream by default and
so hears its own broadcast. Rather than reason about which echoes exist on which
transport, every node renders its own line locally on send and dedupes
everything by message id.

### Why not a `DataStream`?

A data stream would be the obvious choice for a mesh, and `StreamDataType.string`
with `StreamParticipationMode.allNodes` does give every node a direct path to
every other. But late joiners are not wired into an existing stream's inlets, so
the room would be fixed from the moment the stream started. Chat needs people to
come and go, which is exactly what the user-message channel tolerates. Data
streams are the right tool for a known set of nodes sampling at a rate.

## The coordinator is the room's host

A room lasts exactly as long as its coordinator. That is
`CoordinatorLossPolicy.endSession`, which
[`chat_session.dart`](lib/src/chat/chat_session.dart) states explicitly rather
than inheriting: when the coordinator goes, every other node's session ends,
a `SessionEndedEvent` arrives, and everyone lands back on the connect screen
with a line saying why.

It applies whether the host leaves cleanly or its process is killed. A clean
departure broadcasts a `sessionEnd` message, so the others know within a round
trip; a host that vanishes is noticed when it misses `nodeTimeout` (6 s here).
Either way the composer stops accepting lines — a send after the session ends
throws rather than going nowhere.

Reconnecting builds a whole new session, so whoever gets there first finds
nobody to defer to and hosts the new room. Same room name, new room.

The alternative is `CoordinatorLossPolicy.reelect`, where the survivors elect a
new coordinator between themselves and the session carries on. That is the right
choice for a long-running measurement session; it is a worse fit here, where
"who is the host" and "which room is this" are the same question. Pass it to
`ChatSession` to see the difference.

## What to try

- **Watch the election.** Start one instance, then a second: the first shows
  *coordinator*, the second *participant*.
- **Three-way relay.** With three nodes, a message from one participant reaches
  the other participant through the coordinator, still attributed to its author.
- **Heartbeat eviction.** Kill a participant instead of leaving cleanly. The
  others drop it from the roster once it misses `nodeTimeout` (6 s here), and it
  is told it was dropped rather than left to work it out.
- **Kill the coordinator.** Every survivor returns to the connect screen. Rejoin
  from one of them and it becomes the host of a new room; rejoin from a second
  and it joins as a participant.
- **Swap the transport.** Run the same room in Relay and then in Direct. Nothing
  about the chat changes, which is the point; what changes is that in Direct the
  hub stops seeing the messages.

## Platform notes

- **macOS** needs the `com.apple.security.network.client` entitlement, which is
  set in both `DebugProfile.entitlements` and `Release.entitlements`.
- **Android** needs `INTERNET`, plus `usesCleartextTraffic` for plain `ws://`
  during development. Both are in the manifest.
- **Web**: a page served over `https:` may only open a `wss:` socket. Serving the
  app over plain `http:` (as `flutter run -d chrome` does) works with `ws://`.
- **Chrome and direct mode**: Chrome replaces its host candidates with mDNS
  `.local` names unless a site has been granted media permission. Peers that
  resolve mDNS pair up on them directly; ones that do not still connect, from
  the peer-reflexive candidates Chrome's own connectivity checks create.
