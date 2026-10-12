import 'dart:typed_data';

import 'record.dart';
import 'stats.dart';

/// The analysis of a set of run logs, grouped by run.
final class Report {
  final List<RunReport> runs;
  const Report(this.runs);

  Map<String, dynamic> toJson() => {
    'runs': [for (final r in runs) r.toJson()],
  };
}

/// One run: every device's log with the same run id.
final class RunReport {
  final String runId;

  /// The header of each device's log.
  final List<RunHeader> devices;
  final List<SenderReport> senders;

  /// One per sender and receiver that exchanged samples, including a device
  /// receiving its own.
  final List<PairReport> pairs;
  final List<InteractiveReport> interactive;

  /// One per two devices that received from each other.
  final List<SymmetryReport> symmetry;

  /// What the logs say went wrong during the run, for a reader to weigh the
  /// numbers by: a device that received nothing from another, receiving
  /// that stopped or was interrupted, streams that were not found.
  final List<String> warnings;

  const RunReport({
    required this.runId,
    required this.devices,
    required this.senders,
    required this.pairs,
    required this.interactive,
    this.symmetry = const [],
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'devices': [for (final d in devices) d.toJson()],
    'senders': [for (final s in senders) s.toJson()],
    'pairs': [for (final p in pairs) p.toJson()],
    'interactive': [for (final i in interactive) i.toJson()],
    'symmetry': [for (final s in symmetry) s.toJson()],
    'warnings': warnings,
  };
}

/// The latency between two devices averaged over both directions.
///
/// A one-way latency is only as good as the clock offset it was computed
/// with, and an error in the offset adds to one direction what it takes
/// from the other. The sum of the two directions has no offset in it at
/// all, so half of it is known far better than either half; what it cannot
/// say is how the total divides between the directions.
final class SymmetryReport {
  /// Device names.
  final String a;
  final String b;

  /// Mean of the two directions' latency, in seconds.
  final double latencyMean;

  /// The same for the medians. Exact for the mean; for the median, as good
  /// as the offset error is constant over the run.
  final double latencyP50;

  /// The sum of the two directions' offset estimates, in seconds. The true
  /// offsets are equal and opposite, so this is the error of the two
  /// estimates together: the one-way figures are out by about this in total.
  final double offsetInconsistency;

  const SymmetryReport({
    required this.a,
    required this.b,
    required this.latencyMean,
    required this.latencyP50,
    required this.offsetInconsistency,
  });

  Map<String, dynamic> toJson() => {
    'a': a,
    'b': b,
    'latencyMean': latencyMean,
    'latencyP50': latencyP50,
    'offsetInconsistency': offsetInconsistency,
  };
}

/// How regularly one device sent.
final class SenderReport {
  final String device;
  final String? sendMode;
  final int sent;
  final double nominalRate;

  /// Samples per second actually sent; NaN with fewer than two.
  final double achievedRate;

  /// Seconds between consecutive sends.
  final Summary? sendInterval;

  const SenderReport({
    required this.device,
    required this.sendMode,
    required this.sent,
    required this.nominalRate,
    required this.achievedRate,
    required this.sendInterval,
  });

  Map<String, dynamic> toJson() => {
    'device': device,
    'sendMode': sendMode,
    'sent': sent,
    'nominalRate': nominalRate,
    'achievedRate': achievedRate,
    'sendInterval': sendInterval?.toJson(),
  };
}

/// What one device received from one source. Times are seconds.
final class PairReport {
  /// The sender: its device name when its log is among those analysed,
  /// otherwise the source id the receiver knows it by.
  final String from;
  final String sourceId;

  /// The receiver's device name.
  final String to;

  /// Whether the receiver is the sender (no network, no clock offset).
  final bool loopback;

  final String? receiveMode;

  /// Seconds between polls on the receiver, if it polls. A sample waits
  /// between zero and one interval to be seen, so polling adds half of this
  /// to the mean latency and `pollInterval / sqrt(12)` to its spread.
  final double? pollInterval;

  final int received;

  /// Samples the sender logged; null without the sender's log.
  final int? sent;

  /// Samples sent and never received. Without the sender's log, the gaps in
  /// the received sequence numbers (which misses losses at either end).
  final int lost;

  /// Those of [lost] between the first and the last sample received: lost
  /// while the two were exchanging samples.
  final int lostInterior;

  /// Those of [lost] sent before the first sample received or after the
  /// last. The receiver may not have been listening yet, or any more, so
  /// these say more about how the run started and stopped than about the
  /// transport. Null without the sender's log.
  final int? lostEdges;
  final int duplicates;

  /// Samples that arrived after one with a higher sequence number.
  final int reordered;

  /// Samples whose latency is unknown for want of a clock offset.
  final int untimed;

  /// One-way latency: received − (sent + clock offset), using the offset
  /// estimate current when each sample arrived. Can be slightly negative:
  /// the offset is itself an estimate, within ±[uncertainty]/2. That error
  /// moves every value together, so the mean, the extremes and the
  /// percentiles are each only known to within it. The spread is affected
  /// only by how the estimates differ from one another, which
  /// [latencyFitted] removes. For a device's own samples the offset is
  /// zero.
  final Summary? latency;

  /// [latency], but with the offset read from a line fitted through all of
  /// the run's estimates ([ClockReport]) rather than the latest one. This
  /// removes the steps each new estimate puts into [latency].
  final Summary? latencyFitted;

  /// Received − sent with no offset applied. Only meaningful when sender
  /// and receiver share a clock; otherwise it is mostly the clock offset.
  final Summary? latencyRaw;

  /// Round trip of the probes behind the clock offsets; null for a device's
  /// own samples, which need none.
  final Summary? uncertainty;

  /// Seconds between consecutive samples at the sender, by its timestamps.
  final Summary? sendInterval;

  /// Seconds between consecutive arrivals.
  final Summary? receiveInterval;

  final ClockReport? clock;

  /// The per-sample values behind the summaries.
  final PairSeries series;

  const PairReport({
    required this.from,
    required this.sourceId,
    required this.to,
    required this.loopback,
    required this.receiveMode,
    required this.pollInterval,
    required this.received,
    required this.sent,
    required this.lost,
    required this.lostInterior,
    required this.lostEdges,
    required this.duplicates,
    required this.reordered,
    required this.untimed,
    required this.latency,
    required this.latencyFitted,
    required this.latencyRaw,
    required this.uncertainty,
    required this.sendInterval,
    required this.receiveInterval,
    required this.clock,
    required this.series,
  });

  /// Fraction of expected samples that were lost.
  double get lossRate {
    final expected = sent ?? received - duplicates + lost;
    return expected == 0 ? 0 : lost / expected;
  }

  /// [lostInterior] as a fraction of the samples sent between the first and
  /// the last received.
  double get interiorLossRate {
    final expected = received - duplicates + lostInterior;
    return expected == 0 ? 0 : lostInterior / expected;
  }

  Map<String, dynamic> toJson() => {
    'from': from,
    'sourceId': sourceId,
    'to': to,
    'loopback': loopback,
    'receiveMode': receiveMode,
    'pollInterval': pollInterval,
    'received': received,
    'sent': sent,
    'lost': lost,
    'lossRate': lossRate,
    'lostInterior': lostInterior,
    'interiorLossRate': interiorLossRate,
    'lostEdges': lostEdges,
    'duplicates': duplicates,
    'reordered': reordered,
    'untimed': untimed,
    'latency': latency?.toJson(),
    'latencyFitted': latencyFitted?.toJson(),
    'latencyRaw': latencyRaw?.toJson(),
    'uncertainty': uncertainty?.toJson(),
    'sendInterval': sendInterval?.toJson(),
    'receiveInterval': receiveInterval?.toJson(),
    'clock': clock?.toJson(),
  };
}

/// Per-sample values of a [PairReport], in arrival order. NaN is unknown.
final class PairSeries {
  final Int32List seq;
  final Float64List receivedClock;
  final Float64List latency;
  final Float64List latencyFitted;
  final Float64List latencyRaw;
  final Float64List clockOffset;
  final Float64List uncertainty;

  const PairSeries({
    required this.seq,
    required this.receivedClock,
    required this.latency,
    required this.latencyFitted,
    required this.latencyRaw,
    required this.clockOffset,
    required this.uncertainty,
  });
}

/// How a sender's clock relates to the receiver's over the run.
final class ClockReport {
  /// Offset estimates taken (that produced a value).
  final int estimates;

  /// Times the sender's clock was reported reset; the drift fit restarts at
  /// each, and the figures here are for the longest stretch between them.
  final int resets;

  /// Seconds to add to the sender's clock, at the first and last estimate.
  final double offsetFirst;
  final double offsetLast;

  /// How fast the offset changes, in parts per million (µs per second);
  /// null with too few estimates to fit.
  final double? driftPpm;
  final double? driftStdErrPpm;

  /// Spread of the estimates around the fitted line, in seconds.
  final double? residualSd;

  const ClockReport({
    required this.estimates,
    required this.resets,
    required this.offsetFirst,
    required this.offsetLast,
    required this.driftPpm,
    required this.driftStdErrPpm,
    required this.residualSd,
  });

  Map<String, dynamic> toJson() => {
    'estimates': estimates,
    'resets': resets,
    'offsetFirst': offsetFirst,
    'offsetLast': offsetLast,
    'driftPpm': driftPpm,
    'driftStdErrPpm': driftStdErrPpm,
    'residualSd': residualSd,
  };
}

/// The local delays around a sample on one device, from its markers.
final class InteractiveReport {
  final String device;

  /// From a `touch` marker to sending the sample it triggered. The marker
  /// is taken when the application hears of the touch, so the time the
  /// touch screen and the system took to report it is not in this.
  final Summary? touchToSend;

  /// From the time the system stamped a touch with (a `touch_os` marker) to
  /// the application hearing of it; null if the device logged no such
  /// times. The stamp is the system's, often to the millisecond only, and
  /// is itself some time after the finger met the screen.
  final Summary? reportedToHeard;

  /// From receiving a sample to its `shown` marker, by sender. The marker
  /// is taken when the frame has been drawn, not when the display shows it.
  final Map<String, Summary> receiveToShown;

  const InteractiveReport({
    required this.device,
    required this.touchToSend,
    required this.receiveToShown,
    this.reportedToHeard,
  });

  Map<String, dynamic> toJson() => {
    'device': device,
    'touchToSend': touchToSend?.toJson(),
    'reportedToHeard': reportedToHeard?.toJson(),
    'receiveToShown': {
      for (final e in receiveToShown.entries) e.key: e.value.toJson(),
    },
  };
}
