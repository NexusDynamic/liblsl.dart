import 'dart:math' as math;
import 'dart:typed_data';

/// How a channel compares with the others.
enum ChannelFlag { ok, warn, bad }

/// Signal quality of one channel.
class ChannelQuality {
  /// Fraction of the power (0-1) within ±2 Hz of the line frequency.
  final double lineNoise;

  /// Standard deviation over the window (so DC offsets do not count).
  final double rms;

  /// [lineNoise] and [rms] relative to the median of the channels.
  final double lineRatio;
  final double rmsRatio;

  /// Almost no signal: disconnected or saturated.
  final bool flat;

  final ChannelFlag flag;

  const ChannelQuality({
    required this.lineNoise,
    required this.rms,
    required this.lineRatio,
    required this.rmsRatio,
    required this.flat,
    required this.flag,
  });

  static const unknown = ChannelQuality(
    lineNoise: double.nan,
    rms: double.nan,
    lineRatio: double.nan,
    rmsRatio: double.nan,
    flat: false,
    flag: ChannelFlag.ok,
  );

  /// Why the channel is flagged, e.g. "line noise 7.2× median".
  String get reason {
    if (flat) return 'flat signal';
    final parts = <String>[
      if (lineRatio > 1) 'line noise ${lineRatio.toStringAsFixed(1)}× median',
      if (rmsRatio > 1) 'amplitude ${rmsRatio.toStringAsFixed(1)}× median',
    ];
    return parts.join(', ');
  }
}

/// Flags channels whose line noise or amplitude is far above the median of
/// the others (as in the Python live viewer's bad-channel detection).
///
/// Call [update] with the newest raw (unfiltered) samples; the metrics are
/// smoothed over calls with [smoothing] (1 = none).
class QualityTracker {
  /// Line frequency in Hz.
  double lineHz;

  /// Ratios to the median above which a channel is a warning or bad.
  final double warnRatio;
  final double badRatio;

  /// Line noise fractions below this are never flagged, however they
  /// compare with the median.
  final double minLineFraction;

  /// Exponential smoothing factor for each new value.
  final double smoothing;

  Float64List? _line;
  Float64List? _rms;

  QualityTracker({
    this.lineHz = 50,
    this.warnRatio = 3,
    this.badRatio = 6,
    this.minLineFraction = 0.05,
    this.smoothing = 0.1,
  });

  /// Forget the smoothed values.
  void reset() {
    _line = null;
    _rms = null;
  }

  /// Quality of each of [channels] (raw samples at [rate] Hz). Channels in
  /// [exclude] (e.g. already left out of the reference) get values but do
  /// not count towards the medians.
  List<ChannelQuality> update(
    List<List<double>> channels,
    double rate, {
    Set<int> exclude = const {},
  }) {
    final n = channels.length;
    if (_line == null || _line!.length != n) {
      _line = Float64List(n)..fillRange(0, n, double.nan);
      _rms = Float64List(n)..fillRange(0, n, double.nan);
    }
    final line = _line!, rms = _rms!;
    double smooth(double old, double v) {
      if (!v.isFinite) return old;
      return old.isFinite ? old + smoothing * (v - old) : v;
    }

    for (var c = 0; c < n; c++) {
      final (l, r) = _measure(channels[c], rate, lineHz);
      line[c] = smooth(line[c], l);
      rms[c] = smooth(rms[c], r);
    }
    final lineMed = _median([
      for (var c = 0; c < n; c++)
        if (!exclude.contains(c)) line[c],
    ]);
    final rmsMed = _median([
      for (var c = 0; c < n; c++)
        if (!exclude.contains(c)) rms[c],
    ]);
    return [
      for (var c = 0; c < n; c++)
        () {
          if (!line[c].isFinite || !rms[c].isFinite) {
            return ChannelQuality.unknown;
          }
          final lr = lineMed > 0 ? line[c] / lineMed : 1.0;
          final rr = rmsMed > 0 ? rms[c] / rmsMed : 1.0;
          final flat = rms[c] == 0 || (rmsMed > 0 && rr < 0.1);
          final lineScore = line[c] >= minLineFraction ? lr : 1.0;
          final worst = math.max(lineScore, rr);
          final flag = flat || worst > badRatio
              ? ChannelFlag.bad
              : worst > warnRatio
              ? ChannelFlag.warn
              : ChannelFlag.ok;
          return ChannelQuality(
            lineNoise: line[c],
            rms: rms[c],
            lineRatio: lr,
            rmsRatio: rr,
            flat: flat,
            flag: flag,
          );
        }(),
    ];
  }

  /// Line noise fraction and standard deviation of [x], ignoring NaN.
  static (double, double) _measure(List<double> x, double rate, double hz) {
    final values = <double>[
      for (final v in x)
        if (!v.isNaN) v,
    ];
    final n = values.length;
    if (n < 8) return (double.nan, double.nan);
    var mean = 0.0;
    for (final v in values) {
      mean += v;
    }
    mean /= n;
    var sumSq = 0.0;
    final y = Float64List(n);
    for (var i = 0; i < n; i++) {
      final d = values[i] - mean;
      sumSq += d * d;
      // Hann window against leakage from low frequencies.
      y[i] = d * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)));
    }
    final std = math.sqrt(sumSq / n);
    if (hz <= 0 || hz >= rate / 2) return (0, std);
    var total = 0.0;
    for (final v in y) {
      total += v * v;
    }
    if (total == 0) return (0, std);
    // Power in the DFT bins within ±2 Hz of the line (Goertzel), as a
    // fraction of the total (Parseval: sum |X|^2 = n sum y^2; one side of
    // the spectrum counts twice).
    final df = rate / n;
    final k0 = math.max(1, ((hz - 2) / df).ceil());
    final k1 = math.min(n ~/ 2 - 1, ((hz + 2) / df).floor());
    var band = 0.0;
    for (var k = k0; k <= k1; k++) {
      final w = 2 * math.pi * k / n;
      final coeff = 2 * math.cos(w);
      var s1 = 0.0, s2 = 0.0;
      for (final v in y) {
        final s0 = v + coeff * s1 - s2;
        s2 = s1;
        s1 = s0;
      }
      band += s1 * s1 + s2 * s2 - coeff * s1 * s2;
    }
    return ((2 * band / n / total).clamp(0.0, 1.0), std);
  }

  static double _median(List<double> v) {
    final f = [
      for (final x in v)
        if (x.isFinite) x,
    ]..sort();
    if (f.isEmpty) return double.nan;
    final m = f.length ~/ 2;
    return f.length.isOdd ? f[m] : (f[m - 1] + f[m]) / 2;
  }
}
