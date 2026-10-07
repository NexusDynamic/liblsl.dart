import 'dart:typed_data';

import 'record.dart';
import 'report.dart';
import 'stats.dart';

/// Analyses [logs], grouping those of the same run.
///
/// A receiver's log is enough for latency, jitter and clock drift, because
/// every received sample carries the sender's timestamp. The sender's log
/// adds the exact number sent (so losses at the ends of the run count) and
/// its device name.
Report analyse(List<RunLog> logs) {
  final byRun = <String, List<RunLog>>{};
  for (final log in logs) {
    byRun.putIfAbsent(log.header.runId, () => []).add(log);
  }
  return Report([
    for (final entry in byRun.entries) _analyseRun(entry.key, entry.value),
  ]);
}

RunReport _analyseRun(String runId, List<RunLog> logs) {
  final senders = <String, RunLog>{
    for (final log in logs) ?log.header.sourceId: log,
  };
  return RunReport(
    runId: runId,
    devices: [for (final log in logs) log.header],
    senders: [
      for (final log in logs)
        if (log.sent.length > 0) _sender(log),
    ],
    pairs: [
      for (final log in logs)
        for (final entry in log.received.entries)
          _pair(log, entry.key, entry.value, senders[entry.key]),
    ],
    interactive: [
      for (final log in logs)
        if (log.markers.isNotEmpty) _interactive(log, senders),
    ],
  );
}

SenderReport _sender(RunLog log) {
  final clock = log.sent.sendClock;
  final n = clock.length;
  final span = n > 1 ? clock[n - 1] - clock[0] : 0.0;
  return SenderReport(
    device: log.header.deviceName,
    sendMode: log.header.sendMode,
    sent: n,
    nominalRate: log.header.sampleRate,
    achievedRate: span > 0 ? (n - 1) / span : double.nan,
    sendInterval: Summary.of([
      for (var i = 1; i < n; i++) clock[i] - clock[i - 1],
    ]),
  );
}

PairReport _pair(
  RunLog receiver,
  String sourceId,
  ReceivedSeries r,
  RunLog? sender,
) {
  final n = r.length;
  // A device's own samples come back on the clock they were stamped with.
  // Transports that estimate offsets between peers have none for a node to
  // itself, and none is needed: it is zero.
  final loopback = receiver.header.sourceId == sourceId;
  final clock =
      _ClockModel.of(receiver.syncs[sourceId]) ?? _ClockModel.ofReceived(r);

  final latency = Float64List(n);
  final latencyFitted = Float64List(n);
  final latencyRaw = Float64List(n);
  var untimed = 0;
  for (var i = 0; i < n; i++) {
    // NaN in, NaN out: an unknown timestamp or offset leaves the latency
    // unknown rather than guessed.
    final source = r.sourceClock[i];
    latencyRaw[i] = r.receivedClock[i] - source;
    final offset = r.clockOffset[i];
    latency[i] = latencyRaw[i] - (loopback && offset.isNaN ? 0 : offset);
    latencyFitted[i] = clock == null
        ? (loopback ? latency[i] : double.nan)
        : latencyRaw[i] - clock.offsetAt(source);
    if (latency[i].isNaN) untimed++;
  }

  final seen = <int>{};
  var reordered = 0;
  var highest = -1 << 31;
  for (final seq in r.seq) {
    seen.add(seq);
    if (seq < highest) reordered++;
    if (seq > highest) highest = seq;
  }
  final int lost;
  if (sender != null) {
    lost = sender.sent.seq.where((seq) => !seen.contains(seq)).length;
  } else if (seen.isEmpty) {
    lost = 0;
  } else {
    final lowest = seen.reduce((a, b) => a < b ? a : b);
    lost = highest - lowest + 1 - seen.length;
  }

  // Send intervals from the sender's own timestamps, between samples that
  // were consecutive when sent (so a lost sample is not a long interval).
  final bySeq = List<int>.generate(n, (i) => i)
    ..sort((a, b) => r.seq[a].compareTo(r.seq[b]));
  final sendIntervals = <double>[
    for (var k = 1; k < n; k++)
      if (r.seq[bySeq[k]] - r.seq[bySeq[k - 1]] == 1)
        r.sourceClock[bySeq[k]] - r.sourceClock[bySeq[k - 1]],
  ];

  return PairReport(
    from: sender?.header.deviceName ?? sourceId,
    sourceId: sourceId,
    to: receiver.header.deviceName,
    loopback: loopback,
    receiveMode: receiver.header.receiveMode,
    pollInterval: receiver.header.pollInterval,
    received: n,
    sent: sender?.sent.length,
    lost: lost,
    duplicates: n - seen.length,
    reordered: reordered,
    untimed: untimed,
    latency: Summary.of(latency),
    latencyFitted: Summary.of(latencyFitted),
    latencyRaw: Summary.of(latencyRaw),
    uncertainty: Summary.of(r.uncertainty),
    sendInterval: Summary.of(sendIntervals),
    receiveInterval: Summary.of([
      for (var i = 1; i < n; i++) r.receivedClock[i] - r.receivedClock[i - 1],
    ]),
    clock: clock?.report,
    series: PairSeries(
      seq: r.seq,
      receivedClock: r.receivedClock,
      latency: latency,
      latencyFitted: latencyFitted,
      latencyRaw: latencyRaw,
      clockOffset: r.clockOffset,
      uncertainty: r.uncertainty,
    ),
  );
}

InteractiveReport _interactive(RunLog log, Map<String, RunLog> senders) {
  final sendClock = <int, double>{
    for (var i = 0; i < log.sent.length; i++)
      log.sent.seq[i]: log.sent.sendClock[i],
  };
  // First arrival of each sample, by source.
  final receivedClock = <String, Map<int, double>>{
    for (final entry in log.received.entries)
      entry.key: {
        for (var i = entry.value.length - 1; i >= 0; i--)
          entry.value.seq[i]: entry.value.receivedClock[i],
      },
  };

  final touchToSend = <double>[];
  final receiveToShown = <String, List<double>>{};
  for (final marker in log.markers) {
    switch (marker.kind) {
      case 'touch':
        final sent = sendClock[marker.id];
        if (sent != null) touchToSend.add(sent - marker.clock);
      case 'shown':
        final source = marker.sourceId ?? log.header.sourceId;
        final received = receivedClock[source]?[marker.id];
        if (source != null && received != null) {
          receiveToShown
              .putIfAbsent(
                senders[source]?.header.deviceName ?? source,
                () => [],
              )
              .add(marker.clock - received);
        }
    }
  }
  return InteractiveReport(
    device: log.header.deviceName,
    touchToSend: Summary.of(touchToSend),
    receiveToShown: {
      for (final entry in receiveToShown.entries)
        entry.key: ?Summary.of(entry.value),
    },
  );
}

/// The sender's clock offset as a function of the sender's clock: a line
/// per stretch between clock resets.
final class _ClockModel {
  final List<_Segment> _segments;
  final int _resets;

  _ClockModel(this._segments, this._resets);

  /// Null if [syncs] hold no estimate.
  static _ClockModel? of(SyncSeries? syncs) {
    if (syncs == null) return null;
    final segments = <_Segment>[];
    var resets = 0;
    var x = <double>[], y = <double>[];
    void close() {
      if (x.isNotEmpty) segments.add(_Segment(x, y));
      x = [];
      y = [];
    }

    for (var i = 0; i < syncs.length; i++) {
      if (syncs.clockReset[i]) {
        resets++;
        close();
      }
      final offset = syncs.offset[i];
      if (offset.isNaN) continue;
      // Fitted against the sender's clock, which is what a sample's
      // timestamp is read on. Without it, the receiver's clock mapped back
      // is the same instant to within the offset's own error.
      final remote = syncs.remoteTime[i];
      x.add(remote.isNaN ? syncs.receivedClock[i] - offset : remote);
      y.add(offset);
    }
    close();
    return segments.isEmpty ? null : _ClockModel(segments, resets);
  }

  /// The estimates as the samples show them, for a transport that reports
  /// an offset with each sample but not the estimates themselves: every
  /// change of offset is a new estimate, taken about when that sample was
  /// sent. Null if no sample has an offset.
  static _ClockModel? ofReceived(ReceivedSeries r) {
    final x = <double>[], y = <double>[];
    for (var i = 0; i < r.length; i++) {
      final offset = r.clockOffset[i];
      final source = r.sourceClock[i];
      if (offset.isNaN || source.isNaN) continue;
      if (y.isNotEmpty && y.last == offset) continue;
      x.add(source);
      y.add(offset);
    }
    return x.isEmpty ? null : _ClockModel([_Segment(x, y)], 0);
  }

  double offsetAt(double sourceClock) {
    var segment = _segments.first;
    for (final s in _segments) {
      if (s.start <= sourceClock) segment = s;
    }
    return segment.at(sourceClock);
  }

  ClockReport get report {
    final longest = _segments.reduce((a, b) => b.count > a.count ? b : a);
    final fit = longest.fit;
    return ClockReport(
      estimates: _segments.fold(0, (sum, s) => sum + s.count),
      resets: _resets,
      offsetFirst: longest.first,
      offsetLast: longest.last,
      driftPpm: fit == null ? null : fit.slope * 1e6,
      driftStdErrPpm: fit == null || fit.slopeStdErr.isNaN
          ? null
          : fit.slopeStdErr * 1e6,
      residualSd: fit == null || fit.residualSd.isNaN ? null : fit.residualSd,
    );
  }
}

final class _Segment {
  final double start;
  final int count;
  final double first;
  final double last;
  final double mean;

  /// Null with fewer than three estimates: two points always fit exactly,
  /// and extrapolating that line would turn their noise into drift.
  final LinearFit? fit;

  _Segment(List<double> x, List<double> y)
    : start = x.first,
      count = x.length,
      first = y.first,
      last = y.last,
      mean = y.reduce((a, b) => a + b) / y.length,
      fit = x.length < 3 ? null : LinearFit.of(x, y);

  double at(double x) => fit?.at(x) ?? mean;
}
