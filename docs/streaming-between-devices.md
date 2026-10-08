# Streaming data between two devices

This guide sends a stream of samples from one device and receives it on
another, using [`liblsl`](../packages/liblsl), the Dart interface to Lab
Streaming Layer (LSL). At the end, two programs exchange timestamped samples
over the local network and the receiver reports how long each sample took to
arrive.

## Requirements

Both devices need the Dart SDK (3.11 or later) and a C++ compiler, because
`liblsl` is compiled from source the first time a program that uses it is
run. On Debian-based Linux the compiler is installed with
`sudo apt install build-essential clang llvm`.

The devices must be on the same local network. LSL finds streams with
multicast UDP, which some managed networks and firewalls block; the section
[When the stream is not found](#when-the-stream-is-not-found) describes what
to do in that case.

## The examples

The two programs are
[`send.dart`](../packages/liblsl/example/send.dart) and
[`receive.dart`](../packages/liblsl/example/receive.dart). To obtain them,
clone the repository with its submodules on each device:

```bash
git clone --recurse-submodules https://github.com/NexusDynamic/liblsl.dart.git
cd liblsl.dart
dart pub get
cd packages/liblsl
```

## Procedure

1. On the first device, start the sender. It sends a two-channel stream at
   10 Hz for 60 seconds.

   ```bash
   dart run example/send.dart
   ```

2. On the second device, start the receiver. It looks for the stream for up
   to 10 seconds and then prints 50 samples.

   ```bash
   dart run example/receive.dart
   ```

Both programs can also be run in two terminals on one machine, which is a
useful first check because it does not depend on the network.

The receiver prints one line per sample. The following output is from a run
with both programs on one machine:

```text
Clock offset to the sender: -0.052 ms
sample 18: -0.588  sent at 854594.2343 s  latency 1.11 ms
sample 19: -0.309  sent at 854594.3335 s  latency 0.62 ms
sample 20: -0.000  sent at 854594.4339 s  latency 0.83 ms
```

## How the sender works

A stream is described by a stream info: its name and type, the number of
channels, the sampling rate, the data format, and a source id that
identifies the sender. An outlet makes the stream available on the network.

```dart
final info = await LSL.createStreamInfo(
  streamName: 'GuideStream',
  streamType: LSLContentType.custom('Example'),
  channelCount: 2,
  sampleRate: 10.0,
  channelFormat: LSLChannelFormat.double64,
  sourceId: 'guide-sender-1',
);
final outlet = await LSL.createOutlet(streamInfo: info);
```

Each call to `pushSample` sends one sample, which is a list with one value
per channel. LSL stamps the sample with the sender's clock at the moment it
is pushed.

```dart
outlet.pushSample([count.toDouble(), sin(2 * pi * 0.5 * count / 10.0)]);
```

## How the receiver works

The receiver resolves the stream by name and opens an inlet on it.

```dart
final streams = await LSL.resolveStreamsByProperty(
  property: LSLStreamProperty.name,
  value: 'GuideStream',
  waitTime: 10.0,
  minStreamCount: 1,
);
final inlet = await LSL.createInlet<double>(streamInfo: streams.first);
```

Every sample arrives with a timestamp, which is a reading of the sender's
clock. The clocks of two devices have unrelated origins, so the timestamp
has to be mapped onto the receiver's clock before it can be compared with
local events. LSL estimates the offset between the two clocks, and the
receiver adds it to the timestamp.

```dart
final offset = await inlet.getTimeCorrection(timeout: 5.0);

final sample = await inlet.pullSample(timeout: 2.0);
final sentAt = sample.timestamp + offset;
final latency = (LSL.localClock() - sentAt) * 1000;
```

The latency printed by the example is the time between the push on the
sender and the pull on the receiver. The example measures the offset once.
Clocks drift apart by tens of microseconds per second, so a program that
runs for longer than a few minutes should measure the offset again at
intervals.

## When the stream is not found

If the receiver reports that no stream was found although the sender is
running, multicast traffic is probably not reaching the receiver. The
firewall on each device must allow the programs to use the local network.
On a network that blocks multicast, the addresses of the devices can be
given to LSL directly, before any other LSL call and on every device:

```dart
LSL.setConfigContent(LSLApiConfig(knownPeers: ['10.0.0.100', '10.0.0.101']));
```

Android and iOS applications need additional permissions for local network
access. They are listed in the
[`liblsl` README](../packages/liblsl/README.md#android).

## Viewing the stream

While the sender is running, the stream can be inspected in
[LSL Viewer](../apps/lsl_viewer) on any desktop or Android device on the
same network, under *LSL > View streams…*.

## Use in a project

`liblsl` is added to a Dart or Flutter project with `dart pub add liblsl`.
The same code runs on Windows, macOS, Linux, Android and iOS.

## Further reading

[A coordinated experiment](./coordinated-experiment.md) builds on streams to
run one procedure on several devices.
[Sharing LSL streams over the network](../packages/lsl_tools/doc/relay.md)
covers web browsers and devices on different networks.
