# Transport Timing Analysis

`transport_timing_analysis` opens the run logs (XDF files) written by
[`transport_timing`](../transport_timing) and shows what they measured:
latency, jitter, loss, and the difference and drift between the clocks of
the devices. The guide
[Validating timing in a lab](../../docs/validating-timing.md) describes the
whole procedure.

The application is [`signal_viewer`](../../packages/signal_viewer) with a
provider for run logs. The plots, zooming and navigation are those of the
viewer, and the analysis is that of
[`timing_core`](../../packages/timing_core).

The [web app](https://nexusdynamic.org/liblsl.dart/transport_timing_analysis/)
reads logs locally in the browser. Version
[2.0.1](https://github.com/NexusDynamic/liblsl.dart/releases/tag/transport_timing_analysis-v2.0.1)
is available for Windows, macOS, Linux and Android
([all releases](https://github.com/NexusDynamic/liblsl.dart/releases?q=transport_timing_analysis&expanded=true));
the macOS build is unsigned and is opened the first time through the context
menu (right-click, *Open*). To run from source:

```bash
flutter run --release            # then open or drop the logs of a run
```

## Display

Each log opens with one tab per sender. A tab has four traces over the run,
in milliseconds:

| Trace | Meaning |
| --- | --- |
| latency | `received − (sent + clock offset)`, with the offset that was current when the sample arrived |
| latency (fitted) | The same, with the offset read from a line fitted through all estimates of the run. This removes the step that each new estimate introduces into the first trace |
| offset change | How far the clock offset has moved since the start of the run. A slope indicates drift |
| offset bound | How well the offset is known: half the round trip of the probe behind it. Latency differences smaller than this are not resolved |

Samples are placed by sequence number at the rate of the run, so a lost
sample appears as a gap in the trace.

The report, opened from the toolbar or the Timing menu, covers every open
log. It has one row for each sender and receiver, with counts, loss,
percentiles, the clock bound, the contribution of polling, and drift.
Selecting a row shows its latency distribution. When all logs of a run are
open together, the report names every sender and counts losses exactly. The
report can be copied as text or JSON.

## Analysis without the application

The logs are ordinary XDF files and also open in
[`lsl_viewer`](../lsl_viewer), pyxdf and other XDF tools;
[`timing_core`](../../packages/timing_core) describes their streams.

```bash
dart run timing_core:analyse tt_*.xdf          # the report as text
dart run timing_core:analyse --json tt_*.xdf
```
