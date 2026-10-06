# timing_core

The record format and analysis behind `transport_timing`: what each device
writes during a timing run, and how the logs become latency, jitter, loss,
clock offset and drift per sender and receiver. Pure Dart, web-safe, no
dependencies.

## Recording

Each device writes one log per run. The header says what was run and how;
logs with the same `runId` are analysed together.

```dart
final log = RunLogWriter(
  StringBuffer(), // or an IOSink
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
```

The `received` and `clockSync` fields are those of `peer_coordinator`'s
`MessageTiming` and `ClockSyncSample`. The file is a line of JSON followed by
CSV rows; `RunLogWriter` documents them.

## Analysing

```dart
final report = analyse([for (final lines in files) RunLog.parse(lines)]);
print(formatReport(report));
```

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
