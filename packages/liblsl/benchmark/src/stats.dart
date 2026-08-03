import 'dart:math' as math;
import 'dart:typed_data';

/// Accumulates latency observations (µs) and computes summary statistics.
class LatencyStats {
  final List<double> _values = [];

  void add(double microseconds) => _values.add(microseconds);

  void addAll(Iterable<double> microseconds) => _values.addAll(microseconds);

  int get count => _values.length;

  bool get isEmpty => _values.isEmpty;

  double get mean =>
      _values.isEmpty ? 0 : _values.reduce((a, b) => a + b) / _values.length;

  double get min => _values.isEmpty ? 0 : _values.reduce(math.min);

  double get max => _values.isEmpty ? 0 : _values.reduce(math.max);

  double get stdDev {
    if (_values.length < 2) return 0;
    final m = mean;
    final sumSq = _values.fold<double>(0, (acc, v) => acc + (v - m) * (v - m));
    return math.sqrt(sumSq / (_values.length - 1));
  }

  /// Percentile via nearest-rank on a sorted copy (q in [0, 100]).
  double percentile(double q) {
    if (_values.isEmpty) return 0;
    final sorted = Float64List.fromList(_values)..sort();
    final rank = (q / 100 * (sorted.length - 1)).round();
    return sorted[rank.clamp(0, sorted.length - 1)];
  }

  double get p50 => percentile(50);
  double get p95 => percentile(95);
  double get p99 => percentile(99);

  Map<String, dynamic> toJson() => {
    'count': count,
    'mean_us': mean,
    'stddev_us': stdDev,
    'min_us': min,
    'max_us': max,
    'p50_us': p50,
    'p95_us': p95,
    'p99_us': p99,
  };
}

/// Result of one benchmark scenario run.
class ScenarioResult {
  final String name;
  final int samplesSent;
  final int samplesReceived;
  final double durationSeconds;
  final LatencyStats latency;
  final int rssDeltaBytes;

  ScenarioResult({
    required this.name,
    required this.samplesSent,
    required this.samplesReceived,
    required this.durationSeconds,
    required this.latency,
    required this.rssDeltaBytes,
  });

  double get achievedRateHz =>
      durationSeconds > 0 ? samplesReceived / durationSeconds : 0;

  /// Inverse throughput in µs per sample (smaller is better).
  double get timePerSampleUs =>
      samplesReceived > 0 ? durationSeconds * 1e6 / samplesReceived : 0;

  double get lossPercent => samplesSent > 0
      ? (samplesSent - samplesReceived) * 100.0 / samplesSent
      : 0;
}
