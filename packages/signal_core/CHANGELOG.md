## 0.2.0

- Samples are kept as the source has them: `SignalWindow.channels` and
  `StreamColumns.channels` are `List<List<double>>`, 64-bit by default,
  and so are the engine's filtered tiles and `LiveProcessor`'s output.
- `SamplePrecision`: `exact` (the default) or `compact` (32-bit floats, half
  the memory) for `ChunkedSignalEngine` and `LiveProcessor`. Envelopes and
  summary pyramids, which are drawn, stay 32-bit.

## 0.1.0

- Initial version, extracted from libhyperscanner 0.4.1: `ChannelRef`,
  `DerivedSpec`, envelope and read requests, `SummaryPyramid`, `Sos`,
  `SosStreamFilter`, `LiveProcessor`, `QualityTracker` and `ByteSource`.
