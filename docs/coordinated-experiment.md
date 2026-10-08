# A coordinated experiment

This guide runs one program on several devices so that they form a session,
exchange data, and follow a common sequence of trials. It uses
[`peer_coordinator`](../packages/peer_coordinator), which provides the
coordination, and [`liblsl_coordinator`](../packages/liblsl_coordinator),
which carries it over Lab Streaming Layer (LSL). At the end, each device
reports its role, the trials announced by the coordinator, and the samples
received from the other devices with their transit times.

## Concepts

A session is a group of devices (nodes) that have found each other under a
shared experiment name and session name. One node is the coordinator and the
others are participants. No device is assigned the role in advance: each
node looks for an existing coordinator when it joins and takes the role if
it finds none.

The coordinator admits nodes up to a maximum, monitors them by heartbeat,
and controls the data streams of the session. When it creates or starts a
stream, every node creates or starts its own end of that stream. The
coordinator can also broadcast messages with a type and a payload, which an
experiment uses to announce events such as the start of a trial.

## Requirements

The requirements are those of
[Streaming data between two devices](./streaming-between-devices.md): the
Dart SDK (3.12 or later for `liblsl_coordinator`), a C++ compiler, and
devices on one local network that permits multicast.

## Procedure

The program is
[`experiment.dart`](../packages/liblsl_coordinator/example/experiment.dart).
It takes the name of the device and the number of devices in the session.

1. On the first device, start the program and wait until it reports its
   role.

   ```bash
   cd packages/liblsl_coordinator
   dart run example/experiment.dart laptop 2
   ```

2. On the second device, start the program with a different name.

   ```bash
   dart run example/experiment.dart tablet 2
   ```

The devices are started one after another. With the default election, two
devices started at the same moment can each take the role of coordinator;
[Choosing the coordinator](#choosing-the-coordinator) describes the
alternatives.

The following output is from a run with both instances on one machine. The
first device printed:

```text
laptop joined as coordinator
laptop: Trial 1
laptop received 0.0 from tablet after 9.46 ms
laptop received 1.0 from tablet after 0.85 ms
laptop received 2.0 from tablet after 0.87 ms
laptop: Trial 2
```

The second device printed:

```text
tablet joined as participant
tablet: Trial 1
tablet received 0.0 from laptop after 5.88 ms
tablet received 1.0 from laptop after 6.75 ms
tablet received 2.0 from laptop after 6.76 ms
tablet: Trial 2
```

## How the program works

### Configuration

Every device creates a session from the same configuration. Devices find
each other by the experiment name and the session name. `maxNodes` is the
number of devices the session accepts, including the coordinator.

```dart
final session = PeerSession.create(
  CoordinationConfig(
    name: 'guide_experiment',
    sessionConfig: CoordinationSessionConfig(
      name: 'session_1',
      maxNodes: devices,
    ),
    transportConfig: LSLTransportConfig(),
  ),
  thisNodeConfig: NodeConfigFactory().defaultConfig().copyWith(name: name),
);
```

### Joining

`join` returns when the device is either the coordinator or a participant
that the coordinator has admitted.

```dart
await session.initialize();
await session.join();
```

### The coordinator

The coordinator waits until all devices are present and then closes the
session to further devices. It creates a data stream, which every
participant then creates as well, and starts it at a scheduled time, two
seconds ahead. The participation mode `allNodes` makes every device both a
sender and a receiver.

```dart
await session.waitForMinNodes(devices);
await session.pauseAcceptingNodes();

final stream = await session.createDataStream(
  DataStreamConfig(
    name: 'Samples',
    channels: 1,
    sampleRate: 2.0,
    dataType: StreamDataType.double64,
    participationMode: StreamParticipationMode.allNodes,
  ),
);
await session.startStream(
  'Samples',
  startAt: DateTime.now().add(const Duration(seconds: 2)),
);
```

It then announces three trials, stops the stream on all devices, and
announces the end.

```dart
for (var trial = 1; trial <= 3; trial++) {
  await session.sendUserMessage('trial', 'Trial $trial', {'trial': trial});
  await Future<void>.delayed(const Duration(seconds: 2));
}

await session.stopStream('Samples');
await session.sendUserMessage('end', 'End of experiment');
```

### The participants

A participant acts on events. When the coordinator starts the stream, the
participant obtains its own end of it. When a message of type `end`
arrives, the participant leaves the session.

```dart
session.events.streamStart.listen((event) async {
  if (!session.isCoordinator) {
    exchange(await session.getDataStream(event.streamName));
  }
});
session.events.userCoordinationMessages.listen((event) {
  print('$name: ${event.description}');
  if (event.messageType == 'end' && !finished.isCompleted) {
    finished.complete();
  }
});
```

### Exchanging data

On every device, `sendData` publishes a sample and `inbox` delivers the
samples of the stream. With the mode `allNodes` a device also receives its
own samples, which the example skips.

```dart
stream.inbox.listen((message) {
  final from = senderOf(message, session);
  if (from == name) return;
  final transit = message.timing?.transitSeconds;
  final ms = transit == null ? '?' : (transit * 1000).toStringAsFixed(2);
  print('$name received ${message.data.first} from $from after $ms ms');
});
```

## Choosing the coordinator

The election is configured by the promotion strategy of the topology. The
default, `PromotionStrategyFirst`, gives the role to the device that started
first. A device takes the role when it finds no coordinator and no earlier
device, so two devices that start at the same moment, before either is
visible to the other, can both take it. In a test with two instances started
together on one machine, each became coordinator and the session did not
form.

`PromotionStrategyRandom` decides by a random number that each device draws,
and in three such simultaneous starts it produced one coordinator each time:

```dart
topologyConfig: HierarchicalTopologyConfig(
  promotionStrategy: PromotionStrategyRandom(),
  maxNodes: devices,
),
```

The roles can also be fixed. A device whose capabilities contain only
`NodeCapability.coordinator` takes the role without an election, and a
device with only `NodeCapability.participant` waits for a coordinator. This
arrangement formed a session in either starting order.

```dart
thisNodeConfig: NodeConfigFactory().defaultConfig().copyWith(
  name: name,
  capabilities: {NodeCapability.coordinator},
),
```

## Timing

Commands from the coordinator travel as messages, and by default each device
acts on a command when the message arrives. The devices then act within the
network latency of one another, and the interval differs from device to
device.

A stream can instead be started at a scheduled time, as in the example.
`startAt` is a time on the coordinator's clock. It is sent as a reading of
the clock that timestamps the coordinator's messages, and each participant
maps it onto its own clock with the offset measured between the two. The
devices therefore start together whether or not their system clocks agree,
to within the uncertainty of the offset and the resolution of their timers.
With two instances on one machine, which share a clock, the two starts were
between 6 and 44 microseconds apart in three runs. Between devices the
uncertainty of the clock offset is added, which
[Validating timing in a lab](./validating-timing.md) measures. User messages
are not scheduled; an experiment that requires a common trial onset sends
the onset time in the payload of the message.

For analysis, events on different devices are aligned by their timestamps.
Every received message carries a `timing` object with the following values,
all in seconds:

| Field | Meaning |
| --- | --- |
| `sourceClock` | The sender's clock when the sample was sent |
| `clockOffset` | The estimated offset that maps the sender's clock onto the receiver's clock |
| `sourceClockLocal` | `sourceClock + clockOffset`: the time of sending on the receiver's clock |
| `receivedClock` | The receiver's clock when the sample was received |
| `uncertainty` | The round-trip time of the measurement behind the offset; the offset is correct to within half of it |
| `transitSeconds` | `receivedClock − sourceClockLocal` |

An experiment should therefore record these values with its data, so that
the order and spacing of events across devices can be established
afterwards to within the stated uncertainty.

Transit times depend on how a device receives samples. A receiver that
polls sees a sample at its next poll, which adds a wait of up to one polling
interval. `LSLTransportConfig(eventDrivenInlets: true)` receives each sample
as it arrives, at the cost of one thread per inlet.
[Validating timing in a lab](./validating-timing.md) describes how to
measure these quantities on the devices of a lab.

## Other transports

The transport is selected by `transportConfig`, and the rest of the program
does not depend on it. `peer_coordinator` includes a WebSocket transport,
which relays through a hub and also runs in web browsers:

```dart
import 'package:peer_coordinator/websocket.dart';

WebSocketTransportConfig(
  hubUri: Uri.parse('ws://localhost:8080'),
  credentials: HubCredentials(session: 'MyGame', secret: '...'),
)
```

The hub is started with
`dart run peer_coordinator:hub --session MyGame --secret-file ./secret`.
[`webrtc_coordinator`](../packages/webrtc_coordinator) provides a
peer-to-peer WebRTC transport that uses the hub for discovery only. The
[`peer_coordinator` README](../packages/peer_coordinator/README.md)
describes the transports and what happens when the coordinator leaves a
session. The example in this guide has been run with the LSL transport
only.

## Use in a project

The packages are added with `dart pub add liblsl_coordinator`, which
includes `peer_coordinator`. A Flutter application uses the same session
code; the
[chat example](../packages/peer_coordinator/example) shows a session
connected to a user interface.

## Further reading

[Validating timing in a lab](./validating-timing.md) measures latency and
clock drift between devices with the same transports.
