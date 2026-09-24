import 'dart:math' as math;
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';

SignalStats columnStats(List<double> x, [int from = 0, int? to]) {
  to ??= x.length;
  final s = SignalStats();
  var n = 0;
  var mn = double.infinity, mx = double.negativeInfinity;
  var shift = double.nan, sum = 0.0, sumSq = 0.0;
  for (var i = from; i < to; i++) {
    final v = x[i];
    if (v.isNaN) continue;
    if (n == 0) shift = v;
    if (v < mn) mn = v;
    if (v > mx) mx = v;
    final d = v - shift;
    sum += d;
    sumSq += d * d;
    n++;
  }
  if (n == 0) return s;
  final m = sum / n;
  return SignalStats(
    mn,
    mx,
    shift + m,
    math.sqrt(math.max(0, sumSq / n - m * m)),
    n,
  );
}

/// Reduce evenly spaced columns (first sample at [start]) to an envelope
/// over [t0, t1] with [bins] bins, like [ChunkedSignalEngine.envelope].
Envelope envelopeOf(
  List<Float64List> cols,
  double start,
  double rate,
  double t0,
  double t1,
  int bins, {
  bool binStats = false,
}) {
  final n = cols.isEmpty ? 0 : cols.first.length;
  final from = ((t0 - start) * rate).floor().clamp(0, n);
  final to = ((t1 - start) * rate).ceil().clamp(from, n);
  final spb = (t1 - t0) * rate / bins;
  final stats = [for (final c in cols) columnStats(c, from, to)];
  if (spb <= 2) {
    final values = [
      for (final c in cols) Float32List.fromList(c.sublist(from, to)),
    ];
    return Envelope(
      samples: true,
      start: start + from / rate,
      step: 1 / rate,
      min: values,
      max: values,
      stats: stats,
      samplingRate: rate,
    );
  }
  Float32List nans() => Float32List(bins)..fillRange(0, bins, double.nan);
  final mins = [for (final _ in cols) nans()];
  final maxs = [for (final _ in cols) nans()];
  final means = binStats ? [for (final _ in cols) nans()] : null;
  final stds = binStats ? [for (final _ in cols) nans()] : null;
  final startF = (t0 - start) * rate;
  for (var c = 0; c < cols.length; c++) {
    final col = cols[c], mn = mins[c], mx = maxs[c];
    var current = -1;
    final acc = SignalStats();
    void flush() {
      if (current >= 0 && means != null) {
        means[c][current] = acc.mean;
        stds![c][current] = acc.std;
      }
    }

    for (var i = from; i < to; i++) {
      final v = col[i];
      if (v.isNaN) continue;
      final b = ((i - startF) / spb).floor();
      if (b < 0 || b >= bins) continue;
      if (mn[b].isNaN || v < mn[b]) mn[b] = v;
      if (mx[b].isNaN || v > mx[b]) mx[b] = v;
      if (means != null) {
        if (b != current) {
          flush();
          acc.clear();
          current = b;
        }
        acc.merge(v, v, v, 0, 1);
      }
    }
    flush();
  }
  return Envelope(
    samples: false,
    start: t0,
    step: (t1 - t0) / bins,
    min: mins,
    max: maxs,
    stats: stats,
    samplingRate: rate,
    binMean: means,
    binStd: stds,
  );
}
