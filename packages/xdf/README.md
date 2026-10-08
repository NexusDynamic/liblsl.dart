# xdf

[![Pub Version](https://img.shields.io/pub/v/xdf)](https://pub.dev/packages/xdf)

`xdf` reads and writes
[XDF](https://github.com/sccn/xdf/wiki/Specifications) (Extensible Data
Format) recordings, the file format of LabRecorder and Lab Streaming Layer.
It is pure Dart and runs on all platforms, including the web.

Clock synchronisation, jitter removal and effective sampling rates follow
the algorithms and defaults of pyxdf. The results are tested against pyxdf
1.17.5 on the example files of xdf-modules (see `test/fixtures`).

To inspect an XDF file without writing code, it can be opened in
[LSL Viewer](https://nexusdynamic.org/liblsl.dart/lsl_viewer/), which is
built on this package. In the web app the file is read locally in the
browser.

[API documentation](https://pub.dev/documentation/xdf/latest/)

## Installation

```bash
dart pub add xdf
```

## Usage

`loadXdf` reads a whole file into memory and corresponds to `load_xdf` in
pyxdf:

```dart
import 'dart:io';

import 'package:xdf/xdf.dart';

void main() {
  final rec = loadXdf(File('session.xdf').readAsBytesSync());
  for (final s in rec.streams) {
    print('${s.info.name}: ${s.length} samples at ${s.effectiveRate} Hz');
  }
}
```

The package has four entry points:

| Entry point | Purpose |
| --- | --- |
| `loadXdf(bytes)` | A whole file in memory, with synchronised clocks (robust fit, detection of clock resets), jitter removal and effective rates |
| `XdfFile.open(ByteSource)` | Files that are too large to load at once |
| `XdfWriter` | Writing a file as data arrives (headers, samples, clock offsets, boundaries, footers), for example to record LSL streams |
| `readChunks`, `readSamples` | The raw chunks of a file |

### Large files

`XdfFile.open` indexes a file in one pass and reads it on demand. For each
regularly sampled stream it builds summary pyramids, from
[`signal_core`](https://pub.dev/packages/signal_core), so that overviews,
zooming and filtered windows are fast. Markers and irregular streams are
kept in memory. A stream without breaks receives exactly the time stamps
that pyxdf assigns.
