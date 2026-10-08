# peer_coordinator

[![Pub Version](https://img.shields.io/pub/v/peer_coordinator)](https://pub.dev/packages/peer_coordinator)

`peer_coordinator` coordinates several devices that take part in one
procedure, such as the devices of a multi-participant experiment. The
devices form a session, one of them is elected coordinator, and the
coordinator controls shared data streams and broadcasts messages so that all
devices act in step. Every message carries the timing needed to align events
across devices.

The coordination logic is independent of how messages are carried. The
package includes an in-memory transport and a WebSocket transport; Lab
Streaming Layer and WebRTC transports are provided by
[`liblsl_coordinator`](https://pub.dev/packages/liblsl_coordinator) and
[`webrtc_coordinator`](https://pub.dev/packages/webrtc_coordinator). The
package is pure Dart and runs on every Dart platform, including the web.

[API documentation](https://pub.dev/documentation/peer_coordinator/latest/) ·
[Guide: a coordinated experiment](https://github.com/NexusDynamic/liblsl.dart/blob/main/docs/coordinated-experiment.md) ·
[Example: a chat application](https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/peer_coordinator/example)

## Installation

```bash
dart pub add peer_coordinator
```

## Sessions

A session is a group of nodes that have found each other under a shared
application name and session name. One node is the coordinator and the
others are participants. The coordinator admits nodes up to `maxNodes`,
monitors them by heartbeat, removes nodes that stop responding, and controls
the life cycle of the session's data streams: create, start, pause, resume,
flush, stop and destroy. Each command is carried out on every node.

## Usage

The following program runs two nodes in one process over the in-memory
transport. With another transport, each node runs on its own device and the
session code is unchanged.

```dart
import 'package:peer_coordinator/in_memory.dart';
import 'package:peer_coordinator/peer_coordinator.dart';

Future<void> main() async {
  // Nodes in one process share a bus.
  final bus = InMemoryBus();

  Future<PeerSession> join(String name) async {
    final session = PeerSession.create(
      CoordinationConfig(
        name: 'my_experiment',
        sessionConfig: CoordinationSessionConfig(name: 'session_1', maxNodes: 2),
        transportConfig: InMemoryTransportConfig(bus: bus),
      ),
      thisNodeConfig: NodeConfigFactory().defaultConfig().copyWith(name: name),
    );
    await session.initialize();
    await session.join();
    return session;
  }

  final first = await join('first');
  final second = await join('second');
  print('first is coordinator: ${first.isCoordinator}');

  // A participant receives what the coordinator announces.
  second.events.userCoordinationMessages.listen(
    (event) => print('second received: ${event.description}'),
  );
  second.events.streamStart.listen((event) async {
    final stream = await second.getDataStream(event.streamName);
    await stream.sendData([1.0, 2.0, 3.0]);
  });

  // The coordinator creates and starts a stream on every node.
  await first.waitForMinNodes(2);
  final stream = await first.createDataStream(
    DataStreamConfig(
      name: 'Samples',
      channels: 3,
      sampleRate: 100.0,
      dataType: StreamDataType.double64,
    ),
  );
  stream.inbox.listen((message) => print('first received: ${message.data}'));
  await first.startStream('Samples');
  await first.sendUserMessage('trial', 'Trial 1', {'trial': 1});

  await Future<void>.delayed(const Duration(milliseconds: 200));
  await second.leave();
  await first.leave();
  await second.dispose();
  await first.dispose();
}
```

### Events

All coordination events arrive on one stream, with typed filters:

```dart
session.events.nodeJoined.listen((e) => print('joined: ${e.node.name}'));
session.events.streamStart.listen((e) => print('start: ${e.streamName}'));
session.events.userMessages.listen((e) => print(e.payload));
session.events.sessionEnded.listen((e) => print('ended: ${e.reason}'));
```

## Data streams

The coordinator creates a stream from a `DataStreamConfig`, and every node
then builds its own end of it. The participation mode determines which nodes
send and which receive:

| Mode | Senders | Receivers |
| --- | --- | --- |
| `sendAllReceiveCoordinator` (default) | all nodes | the coordinator |
| `sendParticipantsReceiveCoordinator` | the participants | the coordinator |
| `allNodes` | all nodes | all nodes |
| `coordinatorOnly` | the coordinator | the participants |

In the current version, participants also receive the samples of a
`sendAllReceiveCoordinator` stream; this is a known issue, and
`sendParticipantsReceiveCoordinator` restricts delivery to the coordinator.

`sendData` publishes one sample and `inbox` delivers received samples. Each
received message has a `timing` object, in seconds:

| Field | Meaning |
| --- | --- |
| `sourceClock` | The sender's clock when the sample was sent |
| `clockOffset` | The estimated offset that maps the sender's clock onto the local clock |
| `sourceClockLocal` | `sourceClock + clockOffset` |
| `receivedClock` | The local clock when the sample was received |
| `uncertainty` | The round-trip time of the measurement behind the offset; the offset is correct to within half of it |
| `transitSeconds` | `receivedClock − sourceClockLocal` |

A value is null when it is not known, for example before the first offset
estimate has been made.

### Scheduled start

By default each node starts a stream when the coordinator's command reaches
it. With `startAt`, every node starts at the same instant:

```dart
await session.startStream(
  'Samples',
  startAt: DateTime.now().add(const Duration(seconds: 2)),
);
```

The time is sent as a reading of the coordinator's transport clock, and each
participant maps it onto its own clock with the measured offset. The nodes
therefore start together to within the uncertainty of that offset and the
resolution of their timers, whether or not their system clocks agree. A time
in the past starts the stream at once, and stopping or destroying the stream
before the time cancels the start.

## Choosing the coordinator

The coordinator is chosen by the promotion strategy of the topology, without
a central authority. Each node looks for an existing coordinator or a better
candidate, and takes the role if it finds none.

| Strategy | Chosen node |
| --- | --- |
| `PromotionStrategyFirst` (default) | The node that started first |
| `PromotionStrategyRandom` | The node with the lowest of the random numbers the nodes draw |

```dart
topologyConfig: HierarchicalTopologyConfig(
  promotionStrategy: PromotionStrategyRandom(),
  maxNodes: 4,
),
```

With `PromotionStrategyFirst`, nodes that start at the same moment can each
take the role before the other is visible; `PromotionStrategyRandom` is the
appropriate choice when devices are started together. The roles can also be
fixed through the capabilities of a node: a node with only
`NodeCapability.coordinator` takes the role without an election, and a node
with only `NodeCapability.participant` waits for a coordinator.

## When the coordinator leaves

Every node monitors the heartbeat of its coordinator, and a coordinator that
shuts down announces it. A clean departure is detected within one round
trip, and an unresponsive coordinator within `nodeTimeout`. What follows is
set by `CoordinationSessionConfig.coordinatorLossPolicy`:

| Policy | Effect |
| --- | --- |
| `endSession` (default) | The session ends. Timers stop, the topology is dropped, and further sends throw. |
| `reelect` | The remaining nodes repeat the election and rebuild the session among themselves. |
| `remainOpen` | Only the event is emitted, for applications that manage recovery themselves. |

Every policy emits a `SessionEndedEvent` with a `SessionEndReason`
(`coordinatorLeft`, `coordinatorTimedOut`, `coordinatorTransportLost`,
`evicted`).

## Transports

A transport is selected by the `ITransportConfig` passed in
`CoordinationConfig`:

| Transport | Import | Intended use |
| --- | --- | --- |
| In-memory | `package:peer_coordinator/in_memory.dart` | Tests, and several nodes in one process |
| Lab Streaming Layer | `package:liblsl_coordinator/transports/lsl.dart` | Local networks and research hardware, with low latency |
| WebSocket hub | `package:peer_coordinator/websocket.dart` | Across networks and in web browsers, relayed through a hub |
| WebRTC | `package:webrtc_coordinator/transports/webrtc.dart` | Peer-to-peer data channels, with the hub used for discovery and signalling |

### Running a hub

The WebSocket and WebRTC transports require a hub, a relay that
authenticates peers with a shared session secret. For WebRTC it carries only
discovery and signalling.

```sh
dart run peer_coordinator:hub --session MyGame --secret-file ./secret
```

Clients connect with:

```dart
import 'package:peer_coordinator/websocket.dart';

WebSocketTransportConfig(
  hubUri: Uri.parse('ws://localhost:8080'),
  credentials: HubCredentials(session: 'MyGame', secret: '...'),
)
```

The hub does not terminate TLS. The
[`deploy/`](https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/peer_coordinator/deploy)
directory contains a reverse-proxy configuration for a deployment behind
`wss://`.

## Writing a transport

A transport implements four types:

| Type | Responsibility |
| --- | --- |
| `ITransportConfig` | Holds the settings; `createTransport()` builds the transport |
| `ITransport` | Supplies a `NetworkStreamFactory` and `createDiscovery` |
| `IDiscovery` | Answers a `DiscoveryQuery` with `PeerHandle`s |
| `NetworkStream` subclasses | Publish (`createOutlet`), subscribe (`addInlet`) and move messages |

Transport selection is on the configuration, so an application that does not
name a transport does not compile it in. Discovery queries are a typed tree,
which a transport either evaluates directly (`DiscoveryQuery.matches`) or
compiles to its own query language, as the LSL transport does for XPath.

Two contracts need particular care. `discoverOnce` must wait for its full
timeout when nothing matches: the election concludes that no better
candidate exists from an empty result after the timeout, so an early return
makes every node elect itself. `PeerHandle.take()` transfers ownership
exactly once: `addInlet` calls it before using the handle, so that a
discovery cycle cannot free a resource that a stream is using.

A transport whose timestamps are not readings of `PeerClock` implements
`ITransportClock`, which scheduled starts are timed against. For relay
transports such as a hub or a bus, `PeerRegistry` and `RelayRouting`
implement the peer table and the subscription fan-out.

## Testing

The in-memory transport runs a complete multi-node session (election, join,
timeout, streams and teardown) in milliseconds and without sockets; see
`test/transports/memory_transport_test.dart`.
