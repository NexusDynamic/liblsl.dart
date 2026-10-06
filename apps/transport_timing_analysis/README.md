# Transport Timing Analysis

Opens the run logs (`.ttlog`) that
[`transport_timing`](../transport_timing) writes, and shows what they
measured: latency, jitter, loss, and how the devices' clocks differ and
drift.

It is [`signal_viewer`](../../packages/signal_viewer) with a provider for run
logs, so the plots, zooming and navigation are the viewer's; the numbers
come from [`timing_core`](../../packages/timing_core).

```bash
flutter run --release            # then open or drop the logs of a run
```

## What you see

**A tab per sender** for each log, with four traces over the run, in
milliseconds:

- **latency**: received − (sent + clock offset), with the offset that was
  current when the sample arrived.
- **latency (fitted)**: the same with the offset read from a line fitted
  through all of the run's estimates, which removes the step each new
  estimate puts into the first trace.
- **offset change**: how far the clock offset has moved since the start of
  the run. A slope is drift.
- **offset bound**: how well the offset is known (half the round trip of
  the probe behind it). Latency differences smaller than this are not
  resolved.

Samples are placed by sequence number at the run's rate, so a lost sample
is a gap in the trace.

**Report** (toolbar, or the Timing menu) covers every log that is open: one
row per sender and receiver with counts, loss, percentiles, the clock bound,
what polling adds, and drift; select a row for its latency distribution.
Open all the logs of a run together and the report names every sender and
counts losses exactly. The report can be copied as text or JSON.

## Without the app

```bash
dart run timing_core:analyse *.ttlog          # the report as text
dart run timing_core:analyse --json *.ttlog
```
