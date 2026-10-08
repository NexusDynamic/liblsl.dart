import 'dart:math' as math;
import 'dart:typed_data';

/// Descriptive statistics of a set of values. Nothing is trimmed: outliers
/// are part of what a timing run measures, and the percentiles show them.
final class Summary {
  final int count;
  final double mean;

  /// Sample standard deviation (n - 1); zero for a single value.
  final double sd;
  final double min;
  final double max;
  final double p50;
  final double p95;
  final double p99;
  final double p999;

  const Summary({
    required this.count,
    required this.mean,
    required this.sd,
    required this.min,
    required this.max,
    required this.p50,
    required this.p95,
    required this.p99,
    required this.p999,
  });

  /// The summary of the finite values in [values], or null if there are
  /// none (NaN marks a value that could not be measured).
  static Summary? of(Iterable<double> values) {
    final sorted = Float64List.fromList([
      for (final v in values)
        if (v.isFinite) v,
    ])..sort();
    final n = sorted.length;
    if (n == 0) return null;

    var sum = 0.0;
    for (final v in sorted) {
      sum += v;
    }
    final mean = sum / n;
    var squares = 0.0;
    for (final v in sorted) {
      final d = v - mean;
      squares += d * d;
    }
    return Summary(
      count: n,
      mean: mean,
      sd: n > 1 ? math.sqrt(squares / (n - 1)) : 0,
      min: sorted.first,
      max: sorted.last,
      p50: _quantile(sorted, 0.5),
      p95: _quantile(sorted, 0.95),
      p99: _quantile(sorted, 0.99),
      p999: _quantile(sorted, 0.999),
    );
  }

  /// Linear interpolation between the two nearest ranks.
  static double _quantile(Float64List sorted, double q) {
    final position = q * (sorted.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }

  Map<String, dynamic> toJson() => {
    'count': count,
    'mean': mean,
    'sd': sd,
    'min': min,
    'max': max,
    'p50': p50,
    'p95': p95,
    'p99': p99,
    'p999': p999,
  };
}

/// An ordinary least-squares line through (x, y) points.
final class LinearFit {
  final int count;
  final double slope;
  final double intercept;

  /// Standard error of [slope]; NaN with fewer than three points.
  final double slopeStdErr;

  /// Standard deviation of the residuals; NaN with fewer than three points.
  final double residualSd;

  const LinearFit({
    required this.count,
    required this.slope,
    required this.intercept,
    required this.slopeStdErr,
    required this.residualSd,
  });

  double at(double x) => intercept + slope * x;

  /// The fit through [x] and [y], or null with fewer than two points or no
  /// spread in [x].
  static LinearFit? of(List<double> x, List<double> y) {
    final n = x.length;
    if (n < 2) return null;
    // Centred: x is a clock reading that can be ~1e6 s with microsecond
    // differences, and the uncentred sums would lose those digits.
    var meanX = 0.0, meanY = 0.0;
    for (var i = 0; i < n; i++) {
      meanX += x[i];
      meanY += y[i];
    }
    meanX /= n;
    meanY /= n;
    var sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = x[i] - meanX;
      sxx += dx * dx;
      sxy += dx * (y[i] - meanY);
    }
    if (sxx == 0) return null;
    final slope = sxy / sxx;
    final intercept = meanY - slope * meanX;

    var residualSd = double.nan, slopeStdErr = double.nan;
    if (n > 2) {
      var sse = 0.0;
      for (var i = 0; i < n; i++) {
        final r = y[i] - (intercept + slope * x[i]);
        sse += r * r;
      }
      residualSd = math.sqrt(sse / (n - 2));
      slopeStdErr = residualSd / math.sqrt(sxx);
    }
    return LinearFit(
      count: n,
      slope: slope,
      intercept: intercept,
      slopeStdErr: slopeStdErr,
      residualSd: residualSd,
    );
  }
}
