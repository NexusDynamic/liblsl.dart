# timing_core

The record format and analysis behind `transport_timing`. Has the alignment 
and clock handling functionality for the benchmarking / testing of the transport layer
in the user's environment.

## Recording

Each device writes one log per run. The header contains run info and
logs with the same `runId` are analysed together.

```dart
final log = RunLogWriter(
  sink, // a BytesSink, to keep the log in memory until the run is over
  RunHeader(
    runId: runId,
    startedAt: DateTime.now(),
    deviceId: 'ipad1',
    deviceName: 'iPad 1',
    sourceId: mySourceId, // how other devices identify what this one sends
    test: 'latency',
    backend: 'lsl-coordinator',
    sampleRate: 1000,
    receiveMode: 'polled',
    pollInterval: 0.001,
  ),
);

log.sent(seq, sendClock);
log.received(
  sourceId,
  seq,
  receivedClock: timing.receivedClock,
  sourceClock: timing.sourceClock,
  clockOffset: timing.clockOffset,
  uncertainty: timing.uncertainty,
);
log.clockSync(sourceId, receivedClock: s.receivedClock, offset: s.offset,
    remoteTime: s.remoteTime, uncertainty: s.uncertainty);

await log.close();
```

The `received` and `clockSync` fields are those of `peer_coordinator`'s
`MessageTiming` and `ClockSyncSample`.

## The file

A log is an XDF file, so it opens in any XDF tool. The run header is in the
file header's `transport_timing` element, as JSON.

| Stream | Channels | Time stamp |
|---|---|---|
| `tt.sent` | `seq` | this device's clock at the send |
| `tt.received`, one per sender (its `source_id`) | `seq`, `source_clock`, `received_clock`, `clock_offset`, `uncertainty` | the sender's clock at the send |
| `tt.clock`, one per sender | `offset`, `remote_time`, `uncertainty`, `reset` | this device's clock at the estimate |
| `tt.markers` | text: `kind id [source]` | this device's clock |
| `tt.events` | text: `name [json]` | this device's clock |

Clocks are in seconds; NaN is a value that was not known. Every clock-offset
estimate is also a standard XDF clock offset of its `tt.received` stream, so
a reader that synchronises clocks maps that stream's time stamps onto the
receiving device's clock, and latency is one subtraction:

```python
streams, _ = pyxdf.load_xdf('tt_run_ipad1.xdf')
rx = next(s for s in streams if s['info']['name'][0] == 'tt.received')
latency = rx['time_series'][:, 2] - rx['time_stamps']   # received_clock − sent
```

## Analysing

```dart
final report = analyse([for (final bytes in files) RunLog.parse(bytes)]);
print(formatReport(report));
```

Or from the command line: `dart run timing_core:analyse [--json] <log>...`

For each sender and receiver, a `PairReport` gives:

- **latency**: received − (sent + clock offset), with the offset estimate
  that was current when the sample arrived, and again with the offset read
  from a line fitted through all of the run's estimates. Nothing is trimmed
  or clamped: slightly negative values are the offset's own error, and the
  spread is the measurement.
- **uncertainty**: the round trip of the probes behind the offsets; the
  offset, and so the latency, is known to within half of it.
- **loss, duplicates, reordering** from sequence numbers.
- **send and receive intervals**.
- **clock**: offset at the start and end of the run and drift in ppm.
- **pollInterval**: if the receiver polls, a sample waits between zero and
  one interval to be seen, which adds half the interval to the mean latency.
  Compare runs by receive mode to separate this from the network.

A receiver's log is enough for all of this except losses at the very start
or end of a run and the sender's device name, which need the sender's log.

## Result Reporting

**Timestamp / Data alignment**

Alignment uses a sample's time stamp and the
clock offset: `time on this clock = time stamp + offset`.

- The time stamp is the sender's clock when it sent (or, for LSL, pushed)
  the sample. So keep in mind for reporting that this doesn't include
  overhead from an application, or latency from a mouse, keyboard, etc
  if you use something to trigger events.
- The offset comes from timed round trips, and the fastest of a burst is
  kept. Whatever the two directions of that round trip each took, the
  offset is wrong by no more than half the round trip: that is the
  `uncertainty` (the whole round trip) and the "±" in the report (half of
  it).
- Between estimates the clocks drift apart, by tens of ppm, which is tens
  of microseconds per second. `residualSd` shows how good the linear fit is.
  If the drift is not linear, it would be visible here.

**Latency reporting**

`latency = received − (time stamp + offset)`. It is resolved no finer than
the offset is known, so a latency below the "±" is indistinguishable from
zero, which also means negative values are possible (but not because you
discovered time travel, just because of the uncertainty).

What `received` means depends on how samples are consumed:

- Event-driven (`LSLInlet.sampleStream()`, WebSocket, WebRTC): the clock is
  read as the sample becomes available to the process. The latency is the
  sender's send path, the network, and the receiver's network stack.
- Polled: the clock is read when the next poll finds the sample, so the
  latency also has a wait of between zero and one poll interval in it.
- A sample that was already waiting when receiving began (before the first
  listen, after a pause) has the time it was collected, not the time it
  arrived, and so do samples held back by `maxBacklog`.
  This is more for diagnostic purposes, to identify if your consumer is keeping
  up with the stream. For reporting latency, it is correct to say that a stalled
  consumer adds latency, but for identifying possible slow points in your
  topology, you might want to exclude the backlog wait.
- A sender that uses chunking may wait until the number of samples required
  by `chunkSize` is met. The first sample in a chunk will have a longer
  wait time than the last.

If you need accurate benchmarking of end to end latency, including hardware,
OS and Application, you can use the interactive benchmark in `transport_timing`
but you will need a seperate device with a high precision clock (e.g. a Bela board),
a photodiode and an FSR sensor. This will allow you to characterise the complete latency
of a "touch" to "display render".
