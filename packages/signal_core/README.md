# signal_core

Format-agnostic engine for viewing large multichannel recordings and live
streams. Pure Dart; works on all platforms, including the web.

- `SummaryPyramid`: min, max, mean and standard deviation over buckets of
  64, 256, 1024… samples, so a view of any length is drawn from a few
  thousand buckets.
- `ChunkedSignalEngine`: answers `EnvelopeRequest`s and `ReadRequest`s for a
  recording that a format splits into chunks (`ChunkedSignalIndex`), with a
  bounded chunk cache, filtered tiles kept between requests and derived
  (filtered, re-referenced) summaries built in the background.
- `DerivedSpec`, `Sos`, `SosStreamFilter`, `applyReference`,
  `LiveProcessor`: display filters (zero-phase for recordings, streaming
  for live data), re-referencing and mean traces.
- `QualityTracker`: per-channel flags for line noise, amplitude and flat
  channels.
- `ByteSource`: random access to a file by path (native), `Blob` (web) or
  bytes in memory.

Formats built on it: `.hsd` (libhyperscanner). XDF is planned.
