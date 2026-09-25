# liblsl_coordinator

A performance-focused Dart library for multi-layer LSL-based device coordination. This library provides a robust foundation for coordinating multiple devices in real-time applications using Lab Streaming Layer (LSL) with support for different communication layers.

## Open file limit

Every LSL outlet, inlet and resolver holds several sockets. On macOS and Linux,
[`liblsl`](https://pub.dev/packages/liblsl) raises the process's open-file
limit when it is loaded, so sessions with many nodes and streams no longer run
into `Too many open files`. If it warns that it could not (e.g. in a sandbox),
raise the limit yourself with `ulimit -n 4096` before starting the app. See the
liblsl README for details.

## Features

- **Multi-layer Architecture**: Support for coordination, gaming, high-frequency, and custom stream layers
- **Automatic Coordinator Discovery**: Devices automatically find existing coordinators or promote themselves
- **Protocol Configuration**: Predefined and custom protocol configurations for different use cases
- **Pausable/Resumable Streams**: Game and sensor streams can be paused and resumed as needed
- **Isolate-based Processing**: Each layer runs in its own isolate for optimal performance
- **Flexible Stream Management**: Support for irregular frequency coordination and regular high-frequency data streams
- **Self-promotion Logic**: Automatic coordinator election when no coordinator is present

## Architecture

The library implements a layered approach where:

1. **Coordination Layer**: Always present, handles device discovery, role assignment, and protocol setup
2. **Data Layers**: Optional layers for specific data types (game, sensors, etc.)
3. **Stream Management**: Each layer has its own outlets and inlets managed in isolates
4. **Protocol System**: Configurable protocols define which layers are active and their properties

## Getting Started

```bash
dart pub add liblsl_coordinator
```

## Usage

Every node runs the same code: it discovers the others over LSL, one of them
is elected coordinator, and the rest join as participants.

```dart
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

Future<void> main() async {
  final config = CoordinationConfig(
    name: 'my_experiment',
    sessionConfig: CoordinationSessionConfig(name: 'session_1', maxNodes: 4),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: 4,
    ),
    streamConfig: CoordinationStreamConfig(
      name: 'coordination',
      sampleRate: 50.0,
    ),
    transportConfig: LSLTransportConfig(coordinationFrequency: 50.0),
  );

  final session = PeerSession.create(
    config,
    thisNodeConfig: NodeConfigFactory().defaultConfig().copyWith(name: 'node_a'),
  );
  await session.initialize();
  await session.join();
  print(session.isCoordinator ? 'coordinator' : 'participant');

  // Messages between nodes...
  session.events.userCoordinationMessages.listen((m) => print(m));
  await session.sendUserMessage('hello', 'Hello from node_a', {});

  // ...and data streams (the coordinator creates and starts them).
  if (session.isCoordinator) {
    await session.createDataStream(
      DataStreamConfig(
        name: 'Samples',
        channels: 2,
        sampleRate: 100.0,
        dataType: StreamDataType.double64,
      ),
    );
    await session.startStream('Samples');
  }

  await session.dispose();
}
```

The transport is pluggable: the same session code runs over the in-memory
transport from [`peer_coordinator`](https://pub.dev/packages/peer_coordinator)
(`package:peer_coordinator/in_memory.dart`, used by the
[example](https://github.com/NexusDynamic/liblsl.dart/blob/main/packages/liblsl_coordinator/example/liblsl_coordinator_example.dart)),
or over WebRTC with
[`webrtc_coordinator`](https://pub.dev/packages/webrtc_coordinator).

For more information, see the [liblsl.dart](https://github.com/NexusDynamic/liblsl.dart) repository.
