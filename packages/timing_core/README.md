# timing_core

[![Pub Version](https://img.shields.io/pub/v/timing_core)](https://pub.dev/packages/timing_core)

`timing_core` defines the record format and the analysis used to
characterise the timing of a transport between devices: one-way latency,
jitter, loss, clock offset and drift for each pair of devices. It is the
basis of the [`transport_timing`](https://github.com/NexusDynamic/liblsl.dart/tree/main/apps/transport_timing)
application and its analysis application, and can be used on its own to log
and analyse timing in another program. The package is pure Dart and runs on
all platforms, including the web.

[API documentation](https://pub.dev/documentation/timing_core/latest/) ·
[Guide: validating timing in a lab](https://github.com/NexusDynamic/liblsl.dart/blob/main/docs/validating-timing.md)

## Installation

```bash
dart pub add timing_core
```

## Recording

Each device writes one log per run. The header describes the run, and logs
with the same `runId` are analysed together.

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
| --- | --- | --- |
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

The same analysis is available from the command line:
`dart run timing_core:analyse [--json] <log>...`

For each sender and receiver, a `PairReport` contains:

| Field | Meaning |
| --- | --- |
| Latency | `received − (sent + clock offset)`, computed with the offset estimate that was current when the sample arrived, and again with the offset read from a line fitted through all estimates of the run. No values are trimmed or clamped: slightly negative values reflect the error of the offset, and the spread is part of the measurement |
| Uncertainty | The round-trip time of the probes behind the offsets. The offset, and therefore the latency, is known to within half of it |
| Loss, duplicates, reordering | Derived from sequence numbers |
| Send and receive intervals | The regularity of sending and receiving |
| Clock | The offset at the start and end of the run, and the drift in parts per million |
| `pollInterval` | If the receiver polls, a sample waits between zero and one interval before it is seen, which adds half the interval to the mean latency. Runs are compared by receive mode to separate this from the network |

The log of a receiver is sufficient for all of these except losses at the
very start or end of a run and the device name of the sender, which require
the log of the sender.

## Reporting results

### Alignment of time stamps

Data from different devices are aligned with the time stamp of a sample and
the clock offset: `time on this clock = time stamp + offset`.

The time stamp is the sender's clock when it sent (or, for LSL, pushed) the
sample. It does not include delays inside the sending application, or the
latency of an input device such as a mouse or keyboard that triggered the
event.

The offset is estimated from timed round trips, of which the fastest of each
burst is kept. Whatever the two directions of that round trip each took, the
offset is wrong by no more than half the round trip. The whole round trip is
reported as `uncertainty`, and half of it as the "±" of the report.

Between estimates the clocks drift apart by tens of parts per million, which
is tens of microseconds per second. `residualSd` indicates how well a linear
fit describes the drift; a drift that is not linear is visible there.

### Latency

`latency = received − (time stamp + offset)`. Latency is resolved no more
finely than the offset is known, so a latency below the "±" cannot be
distinguished from zero, and negative values occur for the same reason.

The meaning of `received` depends on how samples are consumed:

| Consumption | When the clock is read | What the latency contains |
| --- | --- | --- |
| Event-driven (`LSLInlet.sampleStream()`, WebSocket, WebRTC) | As the sample becomes available to the process | The send path of the sender, the network, and the network stack of the receiver |
| Polled | When the next poll finds the sample | The same, and a wait of between zero and one polling interval |

A sample that was already waiting when receiving began (before the first
listener, or after a pause) has the time at which it was collected, not the
time at which it arrived. The same applies to samples held back by
`maxBacklog`. This is useful for diagnosing whether a consumer keeps up with
a stream. A stalled consumer does add latency, but for locating slow points
in a topology the wait in the backlog can be excluded.

A sender that uses chunking may wait until the number of samples given by
`chunkSize` is reached. The first sample of a chunk then waits longer than
the last.

End-to-end latency that includes hardware, operating system and application
is measured with the interactive test of `transport_timing`. It requires a
separate device with a high-precision clock (for example a Bela board), a
photodiode and a force-sensitive resistor, and characterises the complete
path from a touch to the rendering of the display.
