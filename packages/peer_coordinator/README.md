# peer_coordinator

Transport-neutral peer coordination for Dart: coordinator election, membership
and heartbeat, and synchronised data streams — over whichever backend you plug
in.

Pure Dart. No `dart:io`, no `dart:isolate`, no `dart:ffi`, so it compiles for
the web as well as the VM. (`tool/web_safety_check.dart` enforces that in CI.)

## What it does

One node in a session becomes the **coordinator**; the rest are
**participants**. The coordinator admits nodes up to `maxNodes`, tracks
liveness by heartbeat, evicts nodes that go silent, and drives the lifecycle of
shared data streams — create, start, pause, resume, flush, stop, destroy — so
every node acts in step.

Which node coordinates is decided by a promotion strategy
(`PromotionStrategyRandom` or `PromotionStrategyFirst`), without a central
authority: each node asks "is there anyone I should defer to?" and the one that
finds nobody takes the role.

## When the coordinator goes away

A session has exactly one membership authority, so losing it is a real event
rather than a degraded mode. Every node watches its coordinator's heartbeat, and
a coordinator that shuts down announces it, so both a clean departure and a dead
process are detected — the first within a round trip, the second within
`nodeTimeout`.

What happens next is `CoordinationSessionConfig.coordinatorLossPolicy`:

| Policy | Effect |
|---|---|
| `endSession` (default) | The session is over. Timers stop, the topology is dropped, and further sends throw rather than publishing into a stream with no consumer. |
| `reelect` | The survivors re-run the election and rebuild the session between themselves. |
| `remainOpen` | Nothing beyond the event. For applications that drive their own recovery. |

Every policy emits `SessionEndedEvent`, carrying a `SessionEndReason`
(`coordinatorLeft`, `coordinatorTimedOut`, `coordinatorTransportLost`,
`evicted`), so there is one place to listen regardless:

```dart
session.events.sessionEnded.listen((e) => print('session over: ${e.reason}'));
```

`endSession` is the default because a session with no coordinator has no
membership authority and no stream lifecycle — carrying on is not a defined
state. Choose `reelect` when the work outlives any one node.

## Choosing a transport

The coordination logic never names a backend. You pick one by choosing an
`ITransportConfig`:

| Transport | Import | Use for |
|---|---|---|
| In-memory | `package:peer_coordinator/in_memory.dart` | tests, and any N-nodes-in-one-process setup |
| Lab Streaming Layer | `package:liblsl_coordinator/transports/lsl.dart` | low-latency LAN, research hardware |

```dart
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/in_memory.dart';

// Every node in a session shares one bus.
final bus = InMemoryBus();

final session = PeerSession.create(
  CoordinationConfig(
    name: 'my_experiment',
    sessionConfig: CoordinationSessionConfig(name: 'Session1', maxNodes: 4),
    transportConfig: InMemoryTransportConfig(bus: bus),
  ),
);

await session.initialize();
await session.join();

if (session.isCoordinator) {
  await session.waitForMinNodes(2);
  final stream = await session.createDataStream(
    DataStreamConfig(
      name: 'Samples',
      channels: 3,
      sampleRate: 100.0,
      dataType: StreamDataType.double64,
    ),
  );
  stream.inbox.listen((message) => print(message.data));
  await session.startStream('Samples');
}

await session.leave();
await session.dispose();
```

Events are one stream with typed filters:

```dart
session.events.nodeJoined.listen((e) => print('joined: ${e.node.id}'));
session.events.streamStart.listen((e) => print('start: ${e.streamName}'));
session.events.userMessages.listen((e) => print(e.payload));
```

## Writing a transport

Implement four things:

- **`ITransportConfig`** — carries your settings, and `createTransport()`
  builds the transport. Transport selection lives on the config rather than in
  a registry so that an application which never names your transport never
  compiles it in.
- **`ITransport`** — supplies a `NetworkStreamFactory` and a `createDiscovery`.
- **`IDiscovery`** — answers `DiscoveryQuery` with `PeerHandle`s. Queries are a
  typed tree, so a transport either evaluates them directly
  (`DiscoveryQuery.matches`) or compiles them to its own query language, as the
  LSL backend does for XPath.
- **`NetworkStream`** subclasses — publish (`createOutlet`), subscribe
  (`addInlet`), and move messages.

Two contracts are easy to get wrong and matter:

**`discoverOnce` must wait out its timeout when nothing matches.** Election
concludes "no better candidate exists" precisely by finding nothing after the
full timeout. Returning early on an empty result makes every node elect itself.

**`PeerHandle.take()` transfers ownership exactly once.** `addInlet` calls it
before touching the handle, so a discovery cycle can never free a resource a
stream is still using.

For relay-style transports (a hub, a bus), `PeerRegistry` and `RelayRouting`
implement the peer table and subscription fan-out for you.

## Testing against it

The in-memory transport runs a full multi-node session — election, join,
timeout, streams, teardown — in milliseconds, with no sockets and no timing
luck. See `test/transports/memory_transport_test.dart`.
