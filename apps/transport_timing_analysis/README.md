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

## Example logs

You can use the logs of a run that was recorded with `transport_timing` on a Linux desktop (i7-7700, wired network) and an Android Pixel-7a (WiFi-ac).
These logs can be found in the [`example_timing_logs`](../shared_resources/example_timing_logs) folder of this repository.

## Display

The logs of one run (up to two files) open with one tab per sender. More
logs than that, such as those of a sweep, open without tabs: they are
looked at in the report, and the report opens the tab of any sender and
receiver asked for. Logs are read and analysed in the background, and the
status bar shows the progress. A tab has four traces over the run, in
milliseconds:

| Trace | Meaning |
| --- | --- |
| latency | `received − (sent + clock offset)`, with the offset that was current when the sample arrived |
| latency (fitted) | The same, with the offset read from a line fitted through all estimates of the run. This removes the step that each new estimate introduces into the first trace |
| offset change | How far the clock offset has moved since the start of the run. A slope indicates drift |
| offset bound | How well the offset is known: half the round trip of the probe behind it. Latency differences smaller than this are not resolved |

Samples are placed by sequence number at the rate of the run, so a lost
sample appears as a gap in the trace.

The report, opened from the toolbar or the Timing menu, covers every open
log. It has one row for each sender and receiver of each run, with the
run, its repetition, send and receive mode, counts, loss, percentiles, the
clock bound, the spread, the contribution of polling, and drift. The rows
can be narrowed down by direction, by send mode and by receive mode, and a
device's own samples left out. Selecting a row shows its run and its
latency distribution below the table; the chart button of a row opens the
latency of that pair over the run in a tab, named for the run's condition
where it was part of a sweep. The logs of the selected run, or all logs,
can be closed from the report. The latency is
computed with the fitted clock offset or with the latest estimate, as
selected above the table. A percentile is left out where a row has too few
samples for it. The report can be copied as text or JSON.

When all logs of a run are open together, the report names every sender,
counts losses exactly, and lists a device that received nothing from
another instead of omitting it. Loss is given for the samples sent between
the first and the last received, with the number sent before or after in
brackets. For two devices that received from each other, the latency
averaged over both directions is shown below the table: no clock offset
enters it, so it is known better than either direction alone. Warnings
from the logs (receiving that stopped or was interrupted, streams that were
not found) are shown at the top of the run.

When the open logs contain several runs of the same condition, a table of
repeated runs gives the median of their medians with the lowest and the
highest. The latency of one direction is known only to within the clock
bound, and one run says little about a condition; see
[Validating timing in a lab](../../docs/validating-timing.md#interpreting-the-results).

## Analysis without the application

The logs are ordinary XDF files and also open in
[`lsl_viewer`](../lsl_viewer), pyxdf and other XDF tools;
[`timing_core`](../../packages/timing_core) describes their streams.

```bash
dart run timing_core:analyse tt_*.xdf          # the report as text
dart run timing_core:analyse --json tt_*.xdf
```
