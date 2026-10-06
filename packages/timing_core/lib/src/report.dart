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

  const RunReport({
    required this.runId,
    required this.devices,
    required this.senders,
    required this.pairs,
    required this.interactive,
  });

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'devices': [for (final d in devices) d.toJson()],
    'senders': [for (final s in senders) s.toJson()],
    'pairs': [for (final p in pairs) p.toJson()],
    'interactive': [for (final i in interactive) i.toJson()],
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
  final int duplicates;

  /// Samples that arrived after one with a higher sequence number.
  final int reordered;

  /// Samples whose latency is unknown for want of a clock offset.
  final int untimed;

  /// One-way latency: received − (sent + clock offset), using the offset
  /// estimate current when each sample arrived. Can be slightly negative:
  /// the offset is itself an estimate, within ±[uncertainty]/2.
  final Summary? latency;

  /// [latency], but with the offset read from a line fitted through all of
  /// the run's estimates ([ClockReport]) rather than the latest one. This
  /// removes the steps each new estimate puts into [latency].
  final Summary? latencyFitted;

  /// Received − sent with no offset applied. Only meaningful when sender
  /// and receiver share a clock; otherwise it is mostly the clock offset.
  final Summary? latencyRaw;

  /// Round trip of the probes behind the clock offsets.
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

  /// From a `touch` marker to sending the sample it triggered.
  final Summary? touchToSend;

  /// From receiving a sample to its `shown` marker, by sender.
  final Map<String, Summary> receiveToShown;

  const InteractiveReport({
    required this.device,
    required this.touchToSend,
    required this.receiveToShown,
  });

  Map<String, dynamic> toJson() => {
    'device': device,
    'touchToSend': touchToSend?.toJson(),
    'receiveToShown': {
      for (final e in receiveToShown.entries) e.key: e.value.toJson(),
    },
  };
}
