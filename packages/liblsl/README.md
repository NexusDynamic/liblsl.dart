# liblsl: Lab Streaming Layer for Dart and Flutter

[![Pub Publisher](https://img.shields.io/pub/publisher/liblsl?style=flat-square)](https://pub.dev/publishers/zeyus.com/packages) [![Pub Version](https://img.shields.io/pub/v/liblsl)](https://pub.dev/packages/liblsl) [![melos](https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat-square)](https://github.com/invertase/melos) [![CI Test](https://github.com/NexusDynamic/liblsl.dart/actions/workflows/test.yml/badge.svg)](https://github.com/NexusDynamic/liblsl.dart/actions/workflows/test.yml) [![status](https://joss.theoj.org/papers/2d813b551058e59edacefd35ea281e40/status.svg)](https://joss.theoj.org/papers/2d813b551058e59edacefd35ea281e40) [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20340247.svg)](https://doi.org/10.5281/zenodo.20340247)

`liblsl` is a Dart interface to [liblsl](https://github.com/sccn/liblsl),
the C++ library of [Lab Streaming Layer](https://labstreaminglayer.org)
(LSL). LSL transmits time series, such as EEG and other physiological
signals, events and markers, between applications and devices on a local
network, and provides the clock synchronisation needed to align them. With
this package a Dart or Flutter application can send and receive LSL streams
and interoperate with any other LSL software, for example LabRecorder.

The package covers the whole C API. The C++ library is compiled from source
by the Dart build hooks and called through FFI, so no separately installed
library is required.

[API documentation](https://pub.dev/documentation/liblsl/latest/) ·
[Guide: streaming data between two devices](https://github.com/NexusDynamic/liblsl.dart/blob/main/docs/streaming-between-devices.md) ·
[JOSS paper](./paper/paper.md) ·
[Review and test guide](./REVIEW_TESTING.md)

## Platforms

Windows, macOS, Linux, Android and iOS are supported. The package has also
been run on the Meta Quest 2 (Android) and, with Dart only, on a Raspberry
Pi 4 (Raspberry Pi OS).

The web is not supported, because liblsl is a native library. For browser
applications, the WebSocket transport of
[`peer_coordinator`](https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/peer_coordinator) and the LSL
bridge of [`lsl_tools`](https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/lsl_tools) relay streams to
and from the browser.

## Installation

```bash
dart pub add liblsl
```

A C++ toolchain is required, since the library is compiled when the
application is first built. On Debian-based Linux:

```bash
sudo apt install build-essential clang llvm
```

Flutter applications use the package in the same way. The
[`liblsl_test`](https://github.com/NexusDynamic/liblsl.dart/tree/main/apps/liblsl_test) application is a working
Flutter example for every supported platform.

## Usage

A sender describes its stream, opens an outlet and pushes samples:

```dart
import 'package:liblsl/lsl.dart';

final info = await LSL.createStreamInfo(
  streamName: 'GuideStream',
  streamType: LSLContentType.custom('Example'),
  channelCount: 2,
  sampleRate: 10.0,
  channelFormat: LSLChannelFormat.double64,
  sourceId: 'guide-sender-1',
);
final outlet = await LSL.createOutlet(streamInfo: info);

outlet.pushSample([1.0, 2.0]);
```

A receiver resolves the stream, opens an inlet and pulls samples. Each
sample has a timestamp on the sender's clock, and the time correction maps
it onto the receiver's clock:

```dart
final streams = await LSL.resolveStreamsByProperty(
  property: LSLStreamProperty.name,
  value: 'GuideStream',
  waitTime: 10.0,
  minStreamCount: 1,
);
final inlet = await LSL.createInlet<double>(streamInfo: streams.first);

final offset = await inlet.getTimeCorrection(timeout: 5.0);
final sample = await inlet.pullSample(timeout: 2.0);
final sentAt = sample.timestamp + offset;
```

Native resources are released explicitly:

```dart
inlet.destroy();
streams.destroy();
outlet.destroy();
info.destroy();
```

These fragments follow [`example/send.dart`](./example/send.dart) and
[`example/receive.dart`](./example/receive.dart), which the
[guide](https://github.com/NexusDynamic/liblsl.dart/blob/main/docs/streaming-between-devices.md) explains step by
step. [`example/liblsl_example.dart`](./example/liblsl_example.dart) shows
several streams in one program.

### Isolates and direct calls

By default every outlet and inlet runs in its own
[isolate](https://dart.dev/language/isolates), so that sending and receiving
do not block the main isolate. Performance can degrade when the number of
streams exceeds the number of CPU cores.

An outlet or inlet created with `useIsolates: false` is called directly
through FFI. The `*Sync` methods, such as `pushSampleSync` and
`pullSampleSync`, are available in this mode and have no asynchronous
overhead, which suits code with strict timing requirements.

### Receiving samples as they arrive

`sampleStream()` delivers each sample when it arrives, together with the
local clock at that moment. It uses one isolate per inlet, which waits
inside the native pull call, so no polling interval is added to the receive
time. `chunkStream()` is the chunked equivalent.

```dart
final subscription = inlet.sampleStream().listen((sample) {
  final latency = sample.receivedClock - (sample.timestamp + offset);
});
await subscription.cancel();
```

The stream reports an `LSLSampleListenerException` if its isolate ends for
any reason other than cancellation. A listener that is slower than the
stream accumulates a queue; the `onBacklog` and `maxBacklog` parameters
report and bound it.

### Chunked transfer

When throughput matters more than per-sample latency, push and pull whole
blocks of samples with one native call. Both a convenience list form and a
flat typed-data fast path (single memmove, no per-element conversion) are
available:

```dart
// List form: one List per sample, channelCount values each.
await outlet.pushChunk([
  [1.0, 2.0],
  [3.0, 4.0],
]);

// Typed fast path: flat, sample-major (Float32List for float32 streams,
// Int16List for int16, ...). Optional per-sample timestamps.
final data = Float32List.fromList([1.0, 2.0, 3.0, 4.0]);
await outlet.pushChunkTyped(data);

// Pulling: with the default timeout of 0.0 this returns everything already
// buffered (up to maxSamples). A nonzero timeout keeps pulling until
// maxSamples samples arrive or the timeout expires — it does not return
// early once some data is there.
final chunk = await inlet.pullChunk(maxSamples: 512);
print('${chunk.sampleCount} samples, first ts ${chunk.timestamps.firstOrNull}');

final typed = await inlet.pullChunkTyped(maxSamples: 512);
final Float32List flat = typed.data as Float32List;
```

In direct mode (`useIsolates: false`) the `*Sync` variants
(`pushChunkSync`, `pullChunkTypedSync`, and the zero-copy
`pullChunkPointerSync`) skip all async overhead. String streams support
the list forms (`pushChunk`/`pullChunk`) but not the typed ones.

### Explicit timestamps and pushthrough

By default a pushed sample is stamped with the current `LSL.localClock()`.
When the data was captured earlier (e.g. an event detected a few ms ago, or
samples read from a device buffer), pass the capture time instead:

```dart
final capturedAt = LSL.localClock() - latency;
await outlet.pushSample(['stimulus_onset'], timestamp: capturedAt);

// pushthrough: false lets liblsl batch samples; true (liblsl's default)
// sends immediately. Works with or without a timestamp.
await outlet.pushSample([1.0, 2.0], pushthrough: false);
await outlet.pushChunk(samples, timestamps: perSampleTimes, pushthrough: true);
```

### Binary string samples

String channels are NUL-terminated in the normal API. To send arbitrary bytes
(including `0x00`) on a string stream, use the binary variants:

```dart
await outlet.pushSampleBytes([Uint8List.fromList([0x01, 0x00, 0x02])]);
final sample = await inlet.pullSampleBytes(timeout: 1.0); // LSLSample<Uint8List>

await outlet.pushChunkBytes(listOfSamplesOfUint8Lists);
final chunk = await inlet.pullChunkBytes(maxSamples: 64);
```

The binary chunk pull keeps pulling until `maxSamples` samples have arrived
or `timeout` expires; use `timeout: 0.0` to take only what is already
buffered.

### Transport options (sync/blocking transfer, buffer units)

Outlets and inlets accept a set of `LSLTransportOptions` applied at
creation:

```dart
final outlet = await LSL.createOutlet(
  streamInfo: info,
  transportOptions: {LSLTransportOptions.syncBlocking},
);

final inlet = await LSL.createInlet<double>(
  streamInfo: streams[0],
  // maxBuffer now means samples, not seconds:
  maxBuffer: 1000,
  transportOptions: {
    LSLTransportOptions.bufsizeInSamples,
    LSLTransportOptions.syncBlocking,
  },
);
```

`syncBlocking` switches the outlet to zero-copy blocking socket writes:
every push hands the buffer directly to each connected consumer and only
returns once the OS has accepted the data for all of them. This reduces CPU
usage and latency jitter for high-bandwidth streams, but:

- each push blocks for as long as the slowest consumer needs (in direct
  mode this stalls the calling isolate);
- it is not compatible with string-format streams (an `ArgumentError`
  is thrown at creation);
- only one thread/isolate may push at a time;
- `bufsizeInSamples` / `bufsizeInThousandths` change the unit of
  `maxBuffer` (they are mutually exclusive).

### Benchmarking

A benchmark suite compares the transport modes and operations; see
[benchmark/README.md](./benchmark/README.md). It runs in CI on every commit
to `main` and on every release, and the results over time are charted in
the [benchmark history](https://nexusdynamic.org/liblsl.dart/dev/bench/).

```sh
dart run benchmark/bin/liblsl_benchmark.dart --smoke
```

## Direct FFI usage

The generated FFI bindings can be used directly by importing `native_liblsl.dart`.

```dart
import 'package:liblsl/native_liblsl.dart';
// Create a simple stream info
final streamNamePtr = "TestStream".toNativeUtf8().cast<Char>();
final streamTypePtr = "EEG".toNativeUtf8().cast<Char>();
final sourceIdPtr = "TestSource".toNativeUtf8().cast<Char>();

final streamInfo = lsl_create_streaminfo(
    streamNamePtr,
    streamTypePtr,
    1, // One channel
    100.0, // 100Hz sample rate
    lsl_channel_format_t.cft_string, // String format
    sourceIdPtr,
);

// Create outlet
final outlet = lsl_create_outlet(streamInfo, 0, 1);

// Create a string sample (as an array of strings)
final sampleStr = "Test Sample".toNativeUtf8().cast<Char>();
final stringArray = malloc<Pointer<Char>>(1);
stringArray[0] = sampleStr;

// Push the sample
final result = lsl_push_sample_str(outlet, stringArray);

// Assert the result
expect(result, 0); // 0 typically means success

// Clean up
lsl_destroy_outlet(outlet);
lsl_destroy_streaminfo(streamInfo);
streamNamePtr.free();
streamTypePtr.free();
sourceIdPtr.free();
sampleStr.free();
stringArray.free();
```

## Network and platform notes

### Multicast

LSL discovers streams with multicast UDP. Managed switches, routers and
firewalls can block multicast, in which case streams on other devices are
not found. The network and the firewall of each device must permit it.

### Networks without multicast

LSL can be used without multicast when the IP addresses of the devices are
known. The configuration is applied before any other LSL call, and on every
device. The options correspond to the
[LSL configuration file](https://labstreaminglayer.readthedocs.io/info/lslapicfg.html).

```dart
LSL.setConfigContent(LSLApiConfig(knownPeers: ['10.0.0.100', '10.0.0.101']));
```

### Android

An application requires the `INTERNET`, `CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_NETWORK_STATE`, and `ACCESS_WIFI_STATE` permissions in its `AndroidManifest.xml`, for the multicast UDP communication that LSL uses.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- ... other AndroidManifest.xml nodes -->
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
</manifest>
```

### iOS

Multicast networking on iOS requires the entitlement
[`com.apple.developer.networking.multicast`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast),
which Apple grants on request to paid developer accounts through the
[Multicast Networking Entitlement Request page](https://developer.apple.com/contact/request/networking-multicast).
Without it, LSL cannot be used on iOS.

The following entries are also required in `Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ... other Info.plist nodes -->
  <key>NSBonjourServices</key>
	<array>
		<string>liblsl._tcp</string>
		<string>liblsl._udp</string>
	</array>
    <key>NSLocalNetworkUsageDescription</key>
	<string>Allow LSL to find other devices and communicate</string>
</dict>
</plist>
```

### macOS and Linux: open file limit

Every outlet, inlet and resolver uses several sockets, and the default limit on open files per process (256 on macOS, 1024 on most Linux desktops) runs out with a few dozen streams: liblsl then logs `Too many open files` and fails to create outlets and inlets.

So on macOS and Linux, loading liblsl raises the process's soft open-file limit:

- A soft limit of 65536 or more is left untouched.
- Otherwise it is raised as far as the system allows (the hard limit, and on macOS `kern.maxfilesperproc`), up to 1048576. The hard limit is never changed and the limit is never lowered.
- If the system refuses (e.g. a sandbox or device management), liblsl prints a warning to stderr and carries on; the limit can then be raised with `ulimit -n`.
- Set the environment variable `LIBLSL_DART_NO_RLIMIT=1` to leave the limit alone.

The limit is per process, so child processes that the application starts inherit the raised limit.

### macOS: network settings

macOS's default TCP buffers are small, which slows high-rate transfers, and `maxfiles` bounds how far the open-file limit can be raised. For demanding setups:

```bash
sudo sysctl -w net.inet.tcp.mssdflt=1420
sudo sysctl -w net.inet.tcp.win_scale_factor=7
sudo sysctl -w net.inet.tcp.sendspace=861275
sudo sysctl -w net.inet.tcp.recvspace=861275
sudo sysctl -w net.inet.tcp.autosndbufmax=8388608
sudo sysctl -w net.inet.tcp.autorcvbufmax=8388608
sudo sysctl -w net.inet.ip.portrange.first=32768
sudo launchctl limit maxfiles 65536 200000
```

These settings last until reboot.

## Testing

```bash
dart test
```

The tests need a few thousand open files; the limit is raised automatically
(see [the open file limit](#macos-and-linux-open-file-limit)). The
[review and test guide](./REVIEW_TESTING.md) describes further options.

## Contributing and support

Contribution guidelines are in [CONTRIBUTING.md](https://github.com/NexusDynamic/liblsl.dart/blob/main/CONTRIBUTING.md),
and participants are expected to uphold the
[Code of Conduct](https://github.com/NexusDynamic/liblsl.dart/blob/main/CODE_OF_CONDUCT.md).
[SUPPORT.md](https://github.com/NexusDynamic/liblsl.dart/blob/main/SUPPORT.md) describes where to ask questions and
discuss features. Security vulnerabilities are reported as described in
[SECURITY.md](https://github.com/NexusDynamic/liblsl.dart/blob/main/SECURITY.md).

[![Matrix chat room](https://img.shields.io/matrix/NexusDynamic%3Aneuro.wang?server_fqdn=matrix.neuro.wang&fetchMode=summary&logo=matrix&label=Matrix%20Chat%20Room)
](https://matrix.to/#/#NexusDynamic:neuro.wang)

## License

This project is licensed under the MIT License; see
[LICENSE](https://github.com/NexusDynamic/liblsl.dart/blob/main/packages/liblsl/LICENSE).

## Acknowledgments

- [liblsl](https://github.com/sccn/liblsl) by Christian A. Kothe and
  contributors, the LSL library
- The [Dart programming language](https://dart.dev/) by Google
