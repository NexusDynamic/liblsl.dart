# signal_core

[![Pub Version](https://img.shields.io/pub/v/signal_core)](https://pub.dev/packages/signal_core)

`signal_core` is a signal engine for viewing large multichannel recordings
and live streams. It is independent of any file format, pure Dart, and runs
on all platforms, including the web. It provides the data handling behind
[`signal_viewer`](https://pub.dev/packages/signal_viewer) and the indexed
reading of large files in [`xdf`](https://pub.dev/packages/xdf).

[API documentation](https://pub.dev/documentation/signal_core/latest/)

## Installation

```bash
dart pub add signal_core
```

## Components

| Component | Purpose |
| --- | --- |
| `SummaryPyramid` | Minimum, maximum, mean and standard deviation over buckets of 64, 256, 1024… samples, so that a view of any length is drawn from a few thousand buckets |
| `ChunkedSignalEngine` | Answers `EnvelopeRequest`s and `ReadRequest`s for a recording that a format divides into chunks (`ChunkedSignalIndex`), with a bounded chunk cache, filtered tiles retained between requests, and derived (filtered, re-referenced) summaries built in the background |
| `DerivedSpec`, `Sos`, `SosStreamFilter`, `applyReference`, `LiveProcessor` | Display filters (zero-phase for recordings, streaming for live data), re-referencing and mean traces |
| `QualityTracker` | Per-channel flags for line noise, amplitude and flat channels |
| `ByteSource` | Random access to a file by path (native platforms), to a `Blob` (web) or to bytes in memory |

The formats currently built on the engine are XDF, through the `xdf`
package, and `.hsd` (libhyperscanner).
