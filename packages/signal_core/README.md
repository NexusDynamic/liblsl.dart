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
| `SignalGenerator`, `SynthSpec`, `SynthRun` | Synthetic test signals, reproducible from a seed, sent in real time with simulated dropouts, jitter and markers |

The formats currently built on the engine are XDF, through the `xdf`
package, and `.hsd` (libhyperscanner).

## Synthetic signals

`SignalGenerator` produces multichannel test signals for exercising a
display or processing pipeline. Each channel is the sum of components
(waveforms, noise and artefacts), and the result depends only on the seed,
so a test can compare output generated in chunks with output generated at
once. `SynthSpec` builds the channels of a preset:

| Preset | Content |
| --- | --- |
| `sines` | Channel n at n times the base frequency, wrapping below the Nyquist frequency, with white noise |
| `testPattern` | A different waveform on each channel: sine, square, sawtooth, chirp, DC, impulses, white, pink and line noise |
| `eegResting` | Pink noise, alpha bursts strongest on posterior channels, and a little line noise; 10-20 labels for up to 20 channels |
| `eegArtefacts` | `eegResting` with blinks strongest on frontal channels, spikes and drift; one channel clips and one is flat |
| `lineNoise` | A slow sine under strong 50 or 60 Hz interference and its harmonics |
| `stress` | A sine and white noise per channel, inexpensive to generate at high channel counts and rates |

```dart
import 'package:signal_core/signal_core.dart';

void main() {
  final generator = const SynthSpec(
    preset: SynthPreset.eegArtefacts,
    channels: 16,
    rate: 500,
    seed: 1,
  ).generator();
  // One second of samples, interleaved by channel, and the blinks, spikes
  // and alpha bursts that began in it.
  final (values, events) = generator.next(500);
  print('${values.length} values, events: $events');
}
```

`SynthRun` sends a generator's samples as they fall due on a clock, with
dropouts and time stamp jitter from `Impairments` and markers from
`MarkerSchedule`. The LSL test outlets of
[`lsl_tools`](https://pub.dev/packages/lsl_tools) and the synthetic source
of [`signal_viewer`](https://pub.dev/packages/signal_viewer) are built on it.
