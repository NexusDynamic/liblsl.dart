# liblsl_coordinator

[![Pub Version](https://img.shields.io/pub/v/liblsl_coordinator)](https://pub.dev/packages/liblsl_coordinator)

`liblsl_coordinator` carries the device coordination of
[`peer_coordinator`](https://pub.dev/packages/peer_coordinator) over Lab
Streaming Layer (LSL). Devices on one local network form a session without a
server, elect a coordinator, and exchange data streams whose samples are
timestamped and clock-corrected by LSL. It is intended for experiments on
local networks and with research hardware, where low latency matters.

The session, its events and its data streams are those of
`peer_coordinator`, which this package re-exports; the
[`peer_coordinator` README](https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/peer_coordinator)
describes them. This package adds the LSL transport.

[API documentation](https://pub.dev/documentation/liblsl_coordinator/latest/) ·
[Guide: a coordinated experiment](https://github.com/NexusDynamic/liblsl.dart/blob/main/docs/coordinated-experiment.md)

## Installation

```bash
dart pub add liblsl_coordinator
```

The package depends on [`liblsl`](https://pub.dev/packages/liblsl) and has
its requirements: a C++ toolchain, a network that permits multicast, and the
platform permissions listed in the
[`liblsl` README](https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/liblsl#network-and-platform-notes).
It runs on Windows, macOS, Linux, Android and iOS.

## Usage

Every device runs the same program. The transport is selected in the
configuration:

```dart
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

final session = PeerSession.create(
  CoordinationConfig(
    name: 'guide_experiment',
    sessionConfig: CoordinationSessionConfig(name: 'session_1', maxNodes: 2),
    transportConfig: LSLTransportConfig(),
  ),
  thisNodeConfig: NodeConfigFactory().defaultConfig().copyWith(name: 'laptop'),
);

await session.initialize();
await session.join();
print(session.isCoordinator ? 'coordinator' : 'participant');
```

[`example/experiment.dart`](./example/experiment.dart) is a complete
program: the coordinator waits for the other devices, starts a data stream
on all of them at a scheduled time, announces three trials and stops. It is
run on each device with a device name and the number of devices:

```bash
dart run example/experiment.dart laptop 2
```

## Transport options

`LSLTransportConfig` has the following options. They are local to a device,
and the devices of a session need not agree on them.

| Option | Default | Meaning |
| --- | --- | --- |
| `lslApiConfig` | LSL defaults | The LSL configuration, for example known peers on a network without multicast, or disabling IPv6 |
| `coordinationFrequency` | 100 Hz | The rate at which coordination messages are sent |
| `eventDrivenInlets` | `false` | Receive each sample as it arrives, with one isolate per inlet |
| `restartFailedListeners` | `true` | With `eventDrivenInlets`, restart the isolate of an inlet if it ends unexpectedly |

### Receiving

By default an inlet is polled, for a data stream at its sample period
(between 0.1 and 10 ms). A sample is then seen up to one polling interval
after it arrives, and that wait is part of its transit time. With
`eventDrivenInlets`, each inlet has an isolate that waits inside the native
pull call: the receive clock is read as the sample arrives and the sample is
forwarded at once. The cost is one thread per inlet, which matters for
streams with many senders on small devices.

Timing between devices can be measured for either mode with
[`transport_timing`](https://github.com/NexusDynamic/liblsl.dart/tree/main/apps/transport_timing).

### Scheduled start

`session.startStream(name, startAt: time)` starts a stream on all devices at
the same instant. With this transport the instant is timed on LSL's clock
and mapped between devices with LSL's time correction.

## Open file limit

Every LSL outlet, inlet and resolver holds several sockets. On macOS and
Linux, `liblsl` raises the open-file limit of the process when it is loaded,
so that sessions with many devices and streams do not fail with
`Too many open files`. If it reports that it could not, for example in a
sandbox, the limit is raised with `ulimit -n 4096` before the application is
started.

## Other transports

The same session code runs over the in-memory and WebSocket transports of
`peer_coordinator`, and over WebRTC with
[`webrtc_coordinator`](https://pub.dev/packages/webrtc_coordinator).
[`example/liblsl_coordinator_example.dart`](./example/liblsl_coordinator_example.dart)
runs several nodes in one process over the in-memory transport.
