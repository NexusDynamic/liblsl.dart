## 0.3.0

- Synthetic test signals. `SignalGenerator` sums `SynthComponent`s per
  channel (`ChannelRecipe`): sine, square, sawtooth, chirp, DC and impulse
  waveforms; white, pink and line noise; drift, spikes, blinks and alpha
  bursts; with optional clipping or a flat channel. The output depends only
  on the seed, however it is divided into chunks, and the onsets of
  transients are reported as `SynthEvent`s.
- `SynthSpec` and `SynthPreset`: sines, a test pattern, resting EEG, EEG
  with artefacts, line noise and a stress signal for high channel counts.
- `SynthRun` paces a generator in real time on a given clock, with
  simulated dropouts and time stamp jitter (`Impairments`) and markers at
  regular intervals or at the signal's events (`MarkerSchedule`).

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
