# timing_core

The record format and analysis behind `transport_timing`: what each device
writes during a timing run, and how the logs become latency, jitter, loss,
clock offset and drift per sender and receiver. Pure Dart, web-safe, no
dependencies beyond `xdf`.

## Recording

Each device writes one log per run. The header says what was run and how;
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
