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
  final warnings = <String>[];
  final pairs = <PairReport>[];
  // By receiving device and source id, to find the two directions between
  // two devices.
  final byEnds = <(String, String), PairReport>{};
  final empty = ReceivedSeries(
    Int32List(0),
    Float64List(0),
    Float64List(0),
    Float64List(0),
    Float64List(0),
  );
  for (final log in logs) {
    for (final entry in log.received.entries) {
      final pair = _pair(log, entry.key, entry.value, senders[entry.key]);
      pairs.add(pair);
      byEnds[(log.header.deviceId, entry.key)] = pair;
    }
    // A device that received nothing from one that sent has no samples to
    // show for it, and would otherwise simply not be mentioned. Its own
    // samples are another matter: not every transport returns them.
    for (final sender in logs) {
      final source = sender.header.sourceId;
      if (log.received.containsKey(unknownSource)) break;
      if (identical(sender, log) || source == null) continue;
      if (sender.sent.length == 0 || log.received.containsKey(source)) continue;
      pairs.add(_pair(log, source, empty, sender));
      warnings.add(
        '${log.header.deviceName} received nothing from '
        '${sender.header.deviceName}, which sent ${sender.sent.length}.',
      );
    }
    warnings.addAll(_eventWarnings(log, senders));
  }

  return RunReport(
    runId: runId,
    devices: [for (final log in logs) log.header],
    senders: [
      for (final log in logs)
        if (log.sent.length > 0) _sender(log),
    ],
    pairs: pairs,
    interactive: [
      for (final log in logs)
        if (log.markers.isNotEmpty) _interactive(log, senders),
    ],
    symmetry: [
      for (var i = 0; i < logs.length; i++)
        for (var j = i + 1; j < logs.length; j++)
          ?_symmetry(
            byEnds[(logs[j].header.deviceId, logs[i].header.sourceId ?? '')],
            byEnds[(logs[i].header.deviceId, logs[j].header.sourceId ?? '')],
          ),
    ],
    warnings: warnings,
  );
}

/// What [log]'s events say went wrong on its device.
List<String> _eventWarnings(RunLog log, Map<String, RunLog> senders) {
  final device = log.header.deviceName;
  String name(Object? source) =>
      senders[source]?.header.deviceName ?? '${source ?? 'unknown'}';
  final interrupted = <String, int>{};
  final out = <String>[];
  for (final event in log.events) {
    final detail = event.detail ?? const <String, dynamic>{};
    switch (event.name) {
      case 'receive_error':
        out.add(
          '$device stopped receiving from ${name(detail['from'])} during '
          'the run (error ${detail['code']}).',
        );
      case 'receive_health' when detail['healthy'] == false:
        final from = name(detail['from']);
        interrupted[from] = (interrupted[from] ?? 0) + 1;
      case 'resolved':
        final expected = detail['expected'];
        final found = detail['found'];
        if (expected is int && found is List && found.length < expected) {
          out.add(
            '$device found ${found.length} of the $expected streams it '
            'expected; it received nothing from the rest.',
          );
        }
    }
  }
  for (final entry in interrupted.entries) {
    out.add(
      '$device was interrupted ${entry.value} time(s) receiving from '
      '${entry.key}: samples were late or missing for that, not for the '
      'network.',
    );
  }
  return out;
}

/// The two directions between two devices taken together; null unless both
/// have latencies and offsets.
SymmetryReport? _symmetry(PairReport? aToB, PairReport? bToA) {
  if (aToB == null || bToA == null) return null;
  final one = aToB.latency, other = bToA.latency;
  final offsetOne = _meanOffset(aToB), offsetOther = _meanOffset(bToA);
  if (one == null || other == null) return null;
  if (offsetOne == null || offsetOther == null) return null;
  // Each latency is out by minus its offset's error, and the errors add up
  // to the sum of the two estimates (the true offsets cancel).
  final inconsistency = offsetOne + offsetOther;
  return SymmetryReport(
    a: aToB.from,
    b: aToB.to,
    latencyMean: (one.mean + other.mean + inconsistency) / 2,
    latencyP50: (one.p50 + other.p50 + inconsistency) / 2,
    offsetInconsistency: inconsistency,
  );
}

/// The mean offset over the samples of [pair] that have a latency.
double? _meanOffset(PairReport pair) {
  final s = pair.series;
  var sum = 0.0, n = 0;
  for (var i = 0; i < s.seq.length; i++) {
    if (!s.latency[i].isFinite) continue;
    sum += s.clockOffset[i];
    n++;
  }
  return n == 0 ? null : sum / n;
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
    sendInterval: Summary.of(
      Float64List.fromList([
        for (var i = 1; i < n; i++) clock[i] - clock[i - 1],
      ]),
    ),
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
  // Some transports estimate one all the same (liblsl, for an inlet to the
  // device's own outlet). It is the estimator's error and nothing else, so
  // it is not applied.
  final clock = loopback
      ? null
      : _ClockModel.of(receiver.syncs[sourceId]) ?? _ClockModel.ofReceived(r);

  final latency = Float64List(n);
  final latencyFitted = Float64List(n);
  final latencyRaw = Float64List(n);
  var untimed = 0;
  for (var i = 0; i < n; i++) {
    // NaN in, NaN out: an unknown timestamp or offset leaves the latency
    // unknown rather than guessed.
    final source = r.sourceClock[i];
    latencyRaw[i] = r.receivedClock[i] - source;
    latency[i] = latencyRaw[i] - (loopback ? 0 : r.clockOffset[i]);
    latencyFitted[i] = clock == null
        ? (loopback ? latency[i] : double.nan)
        : latencyRaw[i] - clock.offsetAt(source, r.receivedClock[i]);
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
  final lowest = seen.isEmpty ? 0 : seen.reduce((a, b) => a < b ? a : b);
  final int lostInterior;
  final int? lostEdges;
  if (sender != null) {
    var interior = 0, edges = 0;
    for (final seq in sender.sent.seq) {
      if (seen.contains(seq)) continue;
      if (seen.isNotEmpty && seq > lowest && seq < highest) {
        interior++;
      } else {
        edges++;
      }
    }
    lostInterior = interior;
    lostEdges = edges;
  } else {
    lostInterior = seen.isEmpty ? 0 : highest - lowest + 1 - seen.length;
    lostEdges = null;
  }
  final lost = lostInterior + (lostEdges ?? 0);

  // Send intervals from the sender's own timestamps, between samples that
  // were consecutive when sent (so a lost sample is not a long interval).
  // Samples nearly always arrive in the order they were sent, and then
  // there is nothing to sort.
  final bySeq = reordered == 0 && n == seen.length
      ? null
      : (List<int>.generate(n, (i) => i)
          ..sort((a, b) => r.seq[a].compareTo(r.seq[b])));
  final sendIntervals = Float64List(n == 0 ? 0 : n - 1);
  var sendIntervalCount = 0;
  for (var k = 1; k < n; k++) {
    final here = bySeq == null ? k : bySeq[k];
    final before = bySeq == null ? k - 1 : bySeq[k - 1];
    if (r.seq[here] - r.seq[before] == 1) {
      sendIntervals[sendIntervalCount++] =
          r.sourceClock[here] - r.sourceClock[before];
    }
  }
  final receiveIntervals = Float64List(n == 0 ? 0 : n - 1);
  for (var i = 1; i < n; i++) {
    receiveIntervals[i - 1] = r.receivedClock[i] - r.receivedClock[i - 1];
  }

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
    lostInterior: lostInterior,
    lostEdges: lostEdges,
    duplicates: n - seen.length,
    reordered: reordered,
    untimed: untimed,
    latency: Summary.of(latency),
    latencyFitted: Summary.of(latencyFitted),
    latencyRaw: Summary.of(latencyRaw),
    uncertainty: loopback ? null : Summary.of(r.uncertainty),
    sendInterval: Summary.of(
      Float64List.sublistView(sendIntervals, 0, sendIntervalCount),
    ),
    receiveInterval: Summary.of(receiveIntervals),
    clock: clock?.report,
    series: PairSeries(
      seq: r.seq,
      receivedClock: r.receivedClock,
      latency: latency,
      latencyFitted: latencyFitted,
      latencyRaw: latencyRaw,
      clockOffset: loopback ? Float64List(n) : r.clockOffset,
      uncertainty: loopback
          ? (Float64List(n)..fillRange(0, n, double.nan))
          : r.uncertainty,
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

  // The system's own time for each touch, where the device logged it.
  final reported = <int, double>{
    for (final marker in log.markers)
      if (marker.kind == 'touch_os') marker.id: marker.clock,
  };

  final touchToSend = <double>[];
  final reportedToHeard = <double>[];
  final receiveToShown = <String, List<double>>{};
  for (final marker in log.markers) {
    switch (marker.kind) {
      case 'touch':
        final sent = sendClock[marker.id];
        if (sent != null) touchToSend.add(sent - marker.clock);
        final stamped = reported[marker.id];
        if (stamped != null) reportedToHeard.add(marker.clock - stamped);
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
    reportedToHeard: Summary.of(reportedToHeard),
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
    var x = <double>[], y = <double>[], u = <double>[];
    var since = double.negativeInfinity;
    void close() {
      if (x.isNotEmpty) segments.add(_Segment(x, y, u, since));
      x = [];
      y = [];
      u = [];
    }

    for (var i = 0; i < syncs.length; i++) {
      if (syncs.clockReset[i]) {
        resets++;
        close();
      }
      final offset = syncs.offset[i];
      if (offset.isNaN) continue;
      if (x.isEmpty) since = syncs.receivedClock[i];
      // Fitted against the sender's clock, which is what a sample's
      // timestamp is read on. Without it, the receiver's clock mapped back
      // is the same instant to within the offset's own error.
      final remote = syncs.remoteTime[i];
      x.add(remote.isNaN ? syncs.receivedClock[i] - offset : remote);
      y.add(offset);
      u.add(syncs.uncertainty[i]);
    }
    close();
    return segments.isEmpty ? null : _ClockModel(segments, resets);
  }

  /// The estimates as the samples show them, for a transport that reports
  /// an offset with each sample but not the estimates themselves: every
  /// change of offset is a new estimate, taken about when that sample was
  /// sent. Null if no sample has an offset.
  static _ClockModel? ofReceived(ReceivedSeries r) {
    final x = <double>[], y = <double>[], u = <double>[];
    for (var i = 0; i < r.length; i++) {
      final offset = r.clockOffset[i];
      final source = r.sourceClock[i];
      if (offset.isNaN || source.isNaN) continue;
      if (y.isNotEmpty && y.last == offset) continue;
      x.add(source);
      y.add(offset);
      u.add(r.uncertainty[i]);
    }
    return x.isEmpty
        ? null
        : _ClockModel([_Segment(x, y, u, double.negativeInfinity)], 0);
  }

  /// The offset for a sample stamped [sourceClock] that arrived at
  /// [receivedClock].
  ///
  /// The stretch is chosen on the receiver's clock, because a
  /// clock reset on the sender/outlet cannot be accounted for on the
  /// sender.
  double offsetAt(double sourceClock, double receivedClock) {
    var segment = _segments.first;
    for (final s in _segments) {
      if (s.since <= receivedClock) segment = s;
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
  /// The receiver's clock at this stretch's first estimate.
  final double since;
  final int count;
  final double first;
  final double last;
  final double mean;

  /// Null with fewer than three estimates: two points always fit exactly,
  /// and extrapolating that line would turn their noise into drift.
  ///
  /// An estimate is within half its probe's round trip of the truth, so one
  /// from a quick probe counts for more than one from a slow probe.
  final LinearFit? fit;

  _Segment(List<double> x, List<double> y, List<double> uncertainty, this.since)
    : count = x.length,
      first = y.first,
      last = y.last,
      mean = y.reduce((a, b) => a + b) / y.length,
      fit = x.length < 3 ? null : LinearFit.of(x, y, sigma: uncertainty);

  double at(double x) => fit?.at(x) ?? mean;
}
