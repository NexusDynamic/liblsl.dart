/// Clock synchronisation and jitter removal, as pyxdf does them (same
/// algorithms and defaults), so that time stamps match pyxdf's.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// How [loadXdf] (and [XdfFile]) process time stamps. The defaults are
/// pyxdf's.
class XdfSyncOptions {
  /// Map every stream's time stamps onto the recording computer's clock
  /// with the stream's clock offsets.
  final bool synchronizeClocks;

  /// Detect clock resets (e.g. a computer restarted during the recording)
  /// and synchronise each part separately.
  final bool handleClockResets;

  /// Replace the time stamps of regular streams by a straight line per
  /// segment (between breaks), which removes jitter.
  final bool dejitterTimestamps;

  /// A gap between samples longer than this many seconds, and than
  /// [jitterBreakSamples] samples, starts a new segment.
  final double jitterBreakSeconds;
  final double jitterBreakSamples;

  final double resetThresholdSeconds;
  final double resetThresholdStds;
  final double resetThresholdOffsetSeconds;
  final double resetThresholdOffsetStds;
  final double winsorThreshold;

  const XdfSyncOptions({
    this.synchronizeClocks = true,
    this.handleClockResets = true,
    this.dejitterTimestamps = true,
    this.jitterBreakSeconds = 1,
    this.jitterBreakSamples = 500,
    this.resetThresholdSeconds = 5,
    this.resetThresholdStds = 5,
    this.resetThresholdOffsetSeconds = 1,
    this.resetThresholdOffsetStds = 10,
    this.winsorThreshold = 0.0001,
  });

  /// The raw time stamps, as recorded.
  static const raw = XdfSyncOptions(
    synchronizeClocks: false,
    dejitterTimestamps: false,
  );
}

/// An inclusive range of indices.
typedef XdfRange = (int, int);

double _median(List<double> x) {
  if (x.isEmpty) return double.nan;
  final s = [...x]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

const double _eps = 2.220446049250313e-16;

/// Segments of consecutive indices between breaks: [breaks] has one entry
/// per pair of neighbours (length n - 1).
List<XdfRange> segmentsBetween(List<bool> breaks) {
  final out = <XdfRange>[];
  var start = 0;
  for (var i = 0; i < breaks.length; i++) {
    if (breaks[i]) {
      out.add((start, i));
      start = i + 1;
    }
  }
  out.add((start, breaks.length));
  return out;
}

List<bool> _clockDiffBreaks(
  List<double> diff,
  double threshStds,
  double threshSecs,
) {
  final median = _median(diff);
  final shift = [for (final d in diff) d - median];
  final mad = _median([for (final s in shift) s.abs()]) + _eps;
  return [
    for (final s in shift) (s / mad).abs() > threshStds && s.abs() > threshSecs,
  ];
}

/// Ranges of clock offsets between clock resets.
List<XdfRange> detectClockResets(
  List<double> times,
  List<double> values,
  XdfSyncOptions o,
) {
  if (times.length <= 1) return [(0, times.length - 1)];
  final timeDiff = [
    for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
  ];
  final valueDiff = [
    for (var i = 1; i < values.length; i++) values[i] - values[i - 1],
  ];
  final timeGlitch = _clockDiffBreaks(
    timeDiff,
    o.resetThresholdStds,
    o.resetThresholdSeconds,
  );
  final valueGlitch = _clockDiffBreaks(
    valueDiff,
    o.resetThresholdOffsetStds,
    o.resetThresholdOffsetSeconds,
  );
  return segmentsBetween([
    for (var i = 0; i < timeDiff.length; i++)
      timeDiff[i] < 0 || (timeGlitch[i] && valueGlitch[i]),
  ]);
}

/// Robust linear regression `y ≈ a + b·x` with the Huber loss, solved by
/// ADMM (pyxdf's `_robust_fit`). Returns `(a, b)`.
(double, double) robustFit(
  List<double> x,
  List<double> y, {
  double rho = 1,
  int iters = 1000,
}) {
  final n = x.length;
  var offset = double.infinity;
  for (final v in x) {
    if (v < offset) offset = v;
  }
  final a1 = Float64List(n);
  for (var i = 0; i < n; i++) {
    a1[i] = x[i] - offset;
  }
  // AᵀA = [[n, Σa], [Σa, Σa²]], Cholesky L = [[l00, 0], [l10, l11]].
  var sa = 0.0, saa = 0.0, sy = 0.0, say = 0.0;
  for (var i = 0; i < n; i++) {
    sa += a1[i];
    saa += a1[i] * a1[i];
    sy += y[i];
    say += a1[i] * y[i];
  }
  final l00 = math.sqrt(n.toDouble());
  final l10 = sa / l00;
  final l11sq = saa - l10 * l10;
  if (!(l11sq > 0)) throw StateError('Singular fit');
  final l11 = math.sqrt(l11sq);
  (double, double) solve(double b0, double b1) {
    // L w = b, then Lᵀ x = w.
    final w0 = b0 / l00;
    final w1 = (b1 - l10 * w0) / l11;
    final x1 = w1 / l11;
    final x0 = (w0 - l10 * x1) / l00;
    return (x0, x1);
  }

  final z = Float64List(n);
  final u = Float64List(n);
  var x0 = 0.0, x1 = 0.0;
  for (var k = 0; k < iters; k++) {
    var b0 = sy, b1 = say;
    for (var i = 0; i < n; i++) {
      final zu = z[i] - u[i];
      b0 += zu;
      b1 += a1[i] * zu;
    }
    (x0, x1) = solve(b0, b1);
    for (var i = 0; i < n; i++) {
      final d = x0 + x1 * a1[i] - y[i] + u[i];
      final dInv = d != 0 ? 1 / d : 0.0;
      final tmp = math.max(0.0, 1 - (1 + 1 / rho) * dInv.abs());
      z[i] = rho / (1 + rho) * d + 1 / (1 + rho) * tmp * d;
      u[i] = d - z[i];
    }
  }
  return (x0 - x1 * offset, x1);
}

/// A linear clock correction: add `a + b·t` to a time stamp `t`.
typedef XdfClockFit = (double a, double b);

/// The clock correction of each range of [times] and [values] (from
/// [detectClockResets]).
List<XdfClockFit> clockFits(
  List<double> times,
  List<double> values,
  List<XdfRange> ranges,
  XdfSyncOptions o,
) {
  final w = o.winsorThreshold;
  return [
    for (final (start, end) in ranges)
      if (start != end)
        () {
          try {
            final (a, b) = robustFit(
              [for (var i = start; i <= end; i++) times[i] / w],
              [for (var i = start; i <= end; i++) values[i] / w],
            );
            return (a * w, b);
          } on StateError {
            return (0.0, 0.0);
          }
        }()
      else
        (values[start], 0.0),
  ];
}

/// Map time stamps [ts] (in place) onto the recorder's clock with the
/// clock offsets [times] and [values]. Returns the clock segments: the
/// ranges of [ts] each correction applies to.
List<XdfRange> synchronizeClock(
  Float64List ts,
  List<double> times,
  List<double> values,
  XdfSyncOptions o,
) {
  if (ts.isEmpty || times.isEmpty) return const [];
  final ranges = o.handleClockResets && times.length > 1
      ? detectClockResets(times, values, o)
      : [(0, times.length - 1)];
  final fits = clockFits(times, values, ranges, o);
  if (ranges.length == 1) {
    final (a, b) = fits.first;
    for (var i = 0; i < ts.length; i++) {
      ts[i] += a + b * ts[i];
    }
    return [(0, ts.length - 1)];
  }
  final segments = <XdfRange>[];
  var tsStart = 0;
  for (var r = 0; r < ranges.length; r++) {
    final stop = ranges[r].$2 + 1;
    int tsStop;
    if (stop < times.length) {
      // Break at the first time stamp closer to the next clock time than
      // to the end of this range.
      final currentEnd = times[ranges[r].$2];
      final nextStart = times[stop];
      tsStop = ts.length;
      for (var i = tsStart; i < ts.length; i++) {
        if (!((ts[i] - currentEnd).abs() < (ts[i] - nextStart).abs())) {
          tsStop = i;
          break;
        }
      }
    } else {
      tsStop = ts.length;
    }
    if (tsStart == tsStop) continue;
    segments.add((tsStart, tsStop - 1));
    final (a, b) = fits[r];
    for (var i = tsStart; i < tsStop; i++) {
      ts[i] += a + b * ts[i];
    }
    tsStart = tsStop;
  }
  return segments;
}

/// The result of [removeJitter].
typedef XdfJitterResult = ({List<XdfRange> segments, double effectiveRate});

/// Replace the time stamps [ts] of a stream at [nominalRate] (in place) by
/// a least-squares line per segment between breaks, and measure the
/// effective rate. Irregular streams (rate 0) are left alone. With
/// [canDropSamples] (e.g. video), time stamps are kept as they are.
XdfJitterResult removeJitter(
  Float64List ts,
  double nominalRate,
  XdfSyncOptions o, {
  bool canDropSamples = false,
}) {
  final n = ts.length;
  if (n == 0) return (segments: const [], effectiveRate: 0);
  if (nominalRate == 0) return (segments: [(0, n - 1)], effectiveRate: 0);
  if (canDropSamples) {
    final duration = n > 1 ? ts[n - 1] - ts[0] : 0.0;
    return (
      segments: [(0, n - 1)],
      effectiveRate: duration > 0 ? (n - 1) / duration : 0,
    );
  }
  final threshold = math.max(
    o.jitterBreakSeconds,
    o.jitterBreakSamples / nominalRate,
  );
  final segments = segmentsBetween([
    for (var i = 1; i < n; i++) (ts[i] - ts[i - 1]).abs() > threshold,
  ]);
  for (final (start, end) in segments) {
    final m = end - start + 1;
    if (m == 1) continue;
    // Least squares t = c0 + c1·i, on times relative to the first for
    // precision.
    final t0 = ts[start];
    var si = 0.0, sii = 0.0, st = 0.0, sit = 0.0;
    for (var i = start; i <= end; i++) {
      final t = ts[i] - t0;
      si += i;
      sii += i.toDouble() * i;
      st += t;
      sit += i * t;
    }
    final det = m * sii - si * si;
    final c1 = (m * sit - si * st) / det;
    final c0 = (st - c1 * si) / m;
    for (var i = start; i <= end; i++) {
      ts[i] = t0 + c0 + c1 * i;
    }
  }
  var count = 0;
  var duration = 0.0;
  for (final (start, end) in segments) {
    count += end - start;
    duration += ts[end] - ts[start];
  }
  return (
    segments: segments,
    effectiveRate: count > 0 && duration > 0 ? count / duration : 0,
  );
}
