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

  /// Interquartile range: the width of the middle half.
  final double iqr;

  /// Median absolute deviation from [p50], unscaled. Unlike [sd], a few
  /// extreme values do not move it.
  final double mad;

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
    required this.iqr,
    required this.mad,
  });

  /// Whether there are enough values for the [q] quantile to be more than
  /// one of the few largest: at least five beyond it.
  bool reliable(double q) => count * (1 - q) >= 5;

  /// The summary of the finite values in [values], or null if there are
  /// none (NaN marks a value that could not be measured).
  static Summary? of(Iterable<double> values) {
    // Into one typed list, without a boxed copy on the way: a long run has
    // hundreds of thousands of values in each of several series.
    final all = values is List<double> ? values : values.toList();
    final finite = Float64List(all.length);
    var n = 0;
    for (var i = 0; i < all.length; i++) {
      final v = all[i];
      if (v.isFinite) finite[n++] = v;
    }
    if (n == 0) return null;
    final sorted = Float64List.sublistView(finite, 0, n);
    _sort(sorted, 0, n - 1);

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
    final median = _quantile(sorted, 0.5);
    return Summary(
      count: n,
      mean: mean,
      sd: n > 1 ? math.sqrt(squares / (n - 1)) : 0,
      min: sorted.first,
      max: sorted.last,
      p50: median,
      p95: _quantile(sorted, 0.95),
      p99: _quantile(sorted, 0.99),
      p999: _quantile(sorted, 0.999),
      iqr: _quantile(sorted, 0.75) - _quantile(sorted, 0.25),
      mad: _mad(sorted, median),
    );
  }

  /// Sorts [a] from [low] to [high], both included.
  ///
  /// The library's sort calls a comparison function for every pair it
  /// looks at; comparing the numbers directly is several times quicker,
  /// which is seconds on the logs of a long run. A quicksort in three
  /// parts (below, equal to and above the pivot), because some series have
  /// few distinct values: the round trip behind a clock offset is the same
  /// for every sample until the next estimate.
  static void _sort(Float64List a, int low, int high) {
    while (high - low > 16) {
      // The median of the first, middle and last value as the pivot, so
      // that a series already in order splits in half.
      final middle = low + ((high - low) >> 1);
      final x = a[low], y = a[middle], z = a[high];
      final pivot = x < y
          ? (y < z ? y : (x < z ? z : x))
          : (x < z ? x : (y < z ? z : y));
      var less = low, i = low, greater = high;
      while (i <= greater) {
        final v = a[i];
        if (v < pivot) {
          a[i++] = a[less];
          a[less++] = v;
        } else if (v > pivot) {
          // Past what is above the pivot already: exchanging one such value
          // for another would only shuffle them, and leaves a series that
          // came in order nearly in order but for its ends, which the next
          // pivot is then picked from.
          while (greater > i && a[greater] > pivot) {
            greater--;
          }
          a[i] = a[greater];
          a[greater--] = v;
        } else {
          i++;
        }
      }
      // The smaller part by recursion and the larger by going round again,
      // which keeps the recursion shallow.
      if (less - low < high - greater) {
        _sort(a, low, less - 1);
        low = greater + 1;
      } else {
        _sort(a, greater + 1, high);
        high = less - 1;
      }
    }
    for (var i = low + 1; i <= high; i++) {
      final v = a[i];
      var j = i - 1;
      while (j >= low && a[j] > v) {
        a[j + 1] = a[j];
        j--;
      }
      a[j + 1] = v;
    }
  }

  /// The median of the distances of [sorted] from [median].
  ///
  /// Below the median the distances fall as the values rise, and above it
  /// they rise, so the two sides are each in order already: merging them
  /// gives the distances in order without sorting a second time.
  static double _mad(Float64List sorted, double median) {
    final n = sorted.length;
    // The first value above the median; those before it are walked down.
    var above = 0;
    while (above < n && sorted[above] <= median) {
      above++;
    }
    var below = above - 1;
    final position = 0.5 * (n - 1);
    final lower = position.floor();
    final upper = position.ceil();
    var atLower = 0.0, atUpper = 0.0;
    for (var rank = 0; rank <= upper; rank++) {
      final double next;
      if (below >= 0 &&
          (above >= n || median - sorted[below] <= sorted[above] - median)) {
        next = (sorted[below--] - median).abs();
      } else {
        next = (sorted[above++] - median).abs();
      }
      if (rank == lower) atLower = next;
      if (rank == upper) atUpper = next;
    }
    if (lower == upper) return atLower;
    return atLower + (atUpper - atLower) * (position - lower);
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
    'iqr': iqr,
    'mad': mad,
  };
}

/// A least-squares line through (x, y) points.
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
  ///
  /// With [sigma], the error scale of each y, a point counts in proportion
  /// to `1 / sigma²`; it is ignored unless every value is finite and above
  /// zero. A sigma far below the typical one is raised to a tenth of the
  /// median, so that no single point decides the line.
  static LinearFit? of(List<double> x, List<double> y, {List<double>? sigma}) {
    final n = x.length;
    if (n < 2) return null;
    final w = _weights(sigma, n);
    // Centred: x is a clock reading that can be ~1e6 s with microsecond
    // differences, and the uncentred sums would lose those digits.
    var sumW = 0.0, meanX = 0.0, meanY = 0.0;
    for (var i = 0; i < n; i++) {
      sumW += w[i];
      meanX += w[i] * x[i];
      meanY += w[i] * y[i];
    }
    meanX /= sumW;
    meanY /= sumW;
    var sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = x[i] - meanX;
      sxx += w[i] * dx * dx;
      sxy += w[i] * dx * (y[i] - meanY);
    }
    if (sxx == 0) return null;
    final slope = sxy / sxx;
    final intercept = meanY - slope * meanX;

    var residualSd = double.nan, slopeStdErr = double.nan;
    if (n > 2) {
      var sse = 0.0;
      for (var i = 0; i < n; i++) {
        final r = y[i] - (intercept + slope * x[i]);
        sse += w[i] * r * r;
      }
      // Weights are scaled to average one, so this is the spread of a point
      // of typical weight.
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

  /// Weights averaging one: `1 / sigma²`, or all one without usable sigmas.
  static List<double> _weights(List<double>? sigma, int n) {
    final ones = List<double>.filled(n, 1);
    if (sigma == null || sigma.length != n) return ones;
    if (sigma.any((s) => !s.isFinite || s <= 0)) return ones;
    final sorted = [...sigma]..sort();
    final floor = sorted[n ~/ 2] / 10;
    final w = [
      for (final s in sigma) 1 / math.pow(math.max(s, floor), 2).toDouble(),
    ];
    final mean = w.reduce((a, b) => a + b) / n;
    return [for (final v in w) v / mean];
  }
}
