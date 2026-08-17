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
dart run peer_coordinator:hub --host 0.0.0.0 --port 8080
```

`--host 0.0.0.0` is what lets phones and other machines reach it; the default
binds to loopback only. The hub is role-blind — it forwards frames and tracks
who is connected, and knows nothing about election, membership or streams.

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

## What to try

- **Watch the election.** Start one instance, then a second: the first shows
  *coordinator*, the second *participant*.
- **Three-way relay.** With three nodes, a message from one participant reaches
  the other participant through the coordinator, still attributed to its author.
- **Heartbeat eviction.** Kill a participant instead of leaving cleanly. The
  others drop it from the roster once it misses `nodeTimeout` (6 s here).
- **Kill the coordinator.** The survivors lose their coordinator; what happens
  next depends on the coordination layer rather than on this app, so watch it
  rather than assume it.

## Platform notes

- **macOS** needs the `com.apple.security.network.client` entitlement, which is
  set in both `DebugProfile.entitlements` and `Release.entitlements`.
- **Android** needs `INTERNET`, plus `usesCleartextTraffic` for plain `ws://`
  during development. Both are in the manifest.
- **Web**: a page served over `https:` may only open a `wss:` socket. Serving the
  app over plain `http:` (as `flutter run -d chrome` does) works with `ws://`.
