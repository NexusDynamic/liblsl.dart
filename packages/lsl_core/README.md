# lsl_core

[![Pub Version](https://img.shields.io/pub/v/lsl_core)](https://pub.dev/packages/lsl_core)

`lsl_core` holds the parts of [Lab Streaming Layer](https://labstreaminglayer.org)
that need no native library: channel formats and a codec for their values,
samples and chunks, clock offsets, and the helpers for receiving and polling
streams. It is pure Dart and runs on all platforms, including the web.

[`liblsl`](https://pub.dev/packages/liblsl) (the FFI bindings) re-exports
its `LSL*` types and adds their native side, so code using `liblsl` sees no
difference. [`lsl_tools`](https://pub.dev/packages/lsl_tools),
[`xdf`](https://pub.dev/packages/xdf) and the coordinators build on it, so
the same types and code are shared instead of copied.

[API documentation](https://pub.dev/documentation/lsl_core/latest/)

## Installation

```bash
dart pub add lsl_core
```

## What is in it

- **Formats and values.** `LSLChannelFormat`, and a little-endian codec for
  every format (`readValues`, `writeValues`, `asFormat`, `typedListFor`):
  values stay in their own format, so nothing is lost on the way. int64 is
  exact where ints are 64-bit; in a browser, ints are JavaScript numbers and
  hold integers exactly only up to ±2^53 (`exactInt64` says which).
- **Samples.** `LSLSample`, `LSLChunk`, `LSLChunkTyped`, `LSLTimedChunk`,
  and `LslChunk`, the chunk the inlet facade hands out.
- **Clocks.** `LSLTimeCorrection`, and `ClockModel`, `ClockHop` and
  `ClockChain`: how a time stamp maps onto this computer's clock, hop by hop,
  with error bounds and latency.
- **The inlet and outlet facade.** `LslBackend`, `LslInlet`, `LslOutlet`
  and their options, which `lsl_tools` implements with liblsl, a WebSocket
  bridge, or nothing (on the web).
- **Receiving and polling.** `receiveChunks` (event-driven with a fallback
  to polling), `drainInlet`, `pullCapacity`, `pollIntervalFor`,
  `ListenerRestartSchedule`, `TimeCorrectionSchedule` and
  `runPreciseInterval`.
- **Configuration and metadata.** `LSLApiConfig`, `LSLContentType`, and
  stream info XML (`buildInfoXml`, `infoField`, `channelsOf`).

## Example

```dart
import 'dart:typed_data';

import 'package:lsl_core/lsl_core.dart';

void main() {
  // Eight bytes per int64, little-endian, exactly.
  final d = ByteData(16);
  writeValues(d, 0, LSLChannelFormat.int64, [(1 << 60) + 1, -7], 2);
  final back = readValues(d, 0, LSLChannelFormat.int64, 2);
  print(back); // [1152921504606846977, -7]
}
```
