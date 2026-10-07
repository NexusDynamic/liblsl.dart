/// What sits between a stream of clock-offset estimates and the timestamps they
/// correct: a drift fit, a timestamp smoother and an arrival-latency window.
///
/// [PeerClockEstimator] reproduces liblsl's estimator and, like it, publishes
/// an offset that *steps* once per burst. liblsl hides the steps in the inlet's
/// post-processing; a transport that maps timestamps itself needs the same two
/// things liblsl has there, which are [ClockModel] (where is the offset now,
/// between estimates) and [TimestampSmoother] (`proc_dejitter`).
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:peer_coordinator/src/coordination/clock_sync.dart';
import 'package:peer_coordinator/src/data/clock_hop.dart';

/// A straight line through the recent offset estimates for one peer.
///
/// Two free-running clocks drift apart at a near-constant rate (tens of ppm),
/// so over a minute the offset is a line, and fitting one gives both a value
/// between estimates and the drift itself. Holds no timers; feed it each
/// accepted [ClockOffsetEstimate].
final class ClockModel {
  ClockModel({this.window = 60, this.minSpan = 10});

  /// Seconds of estimates the fit runs over, on the peer's clock.
  final double window;

  /// Seconds the estimates must span before a slope is fitted. Below it the
  /// drift is reported as zero, since a slope through a few seconds of
  /// millisecond-noisy offsets is noise.
  final double minSpan;

  final List<ClockOffsetEstimate> _estimates = [];
  double _at = 0;
  double _offset = 0;
  double _drift = 0;

  /// Whether any estimate has been accepted. Before that the offset is
  /// unknown, never zero.
  bool get ready => _estimates.isNotEmpty;

  /// Drift in seconds per second of the peer's clock.
  double get drift => _drift;

  /// The **full** round-trip time behind the newest estimate; the offset lies
  /// within ±[uncertainty]/2.
  double get uncertainty => ready ? _estimates.last.uncertainty : double.nan;

  void add(ClockOffsetEstimate estimate) {
    _estimates.add(estimate);
    final oldest = estimate.remoteTime - window;
    _estimates.removeWhere((e) => e.remoteTime < oldest);
    _fit();
  }

  /// Forgets everything — the peer's clock domain may have changed.
  void reset() {
    _estimates.clear();
    _at = _offset = _drift = 0;
  }

  void _fit() {
    final n = _estimates.length;
    var meanT = 0.0, meanO = 0.0;
    for (final e in _estimates) {
      meanT += e.remoteTime / n;
      meanO += e.offset / n;
    }
    var covariance = 0.0, variance = 0.0;
    for (final e in _estimates) {
      final dt = e.remoteTime - meanT;
      covariance += dt * (e.offset - meanO);
      variance += dt * dt;
    }
    final span = _estimates.last.remoteTime - _estimates.first.remoteTime;
    _at = meanT;
    _offset = meanO;
    _drift = span >= minSpan && variance > 0 ? covariance / variance : 0;
  }

  /// Seconds to add to [t] on the peer's clock to get ours.
  double offsetAt(double t) => _offset + _drift * (t - _at);

  /// This model as one hop of a [ClockChain].
  ClockHop hop({
    required String node,
    required String via,
    double? latency,
    double? jitter,
    double? held,
  }) => ClockHop(
    node: node,
    via: via,
    offset: _offset,
    drift: _drift,
    at: _at,
    uncertainty: ready ? uncertainty : 0,
    latency: latency,
    jitter: jitter,
    held: held,
  );
}

/// Smooths the timestamps of a regular-rate stream, as liblsl's
/// `proc_dejitter` does.
///
/// A recursive least-squares fit of timestamp against sample index with a
/// forgetting factor (`time_postprocessor.cpp`): each timestamp is replaced by
/// the line's value at its index, which removes the jitter of *when a sample
/// was stamped* while following the true rate. Only meaningful for streams
/// with a nominal rate.
final class TimestampSmoother {
  /// [halftime] is how long, in seconds, a past sample keeps half its weight;
  /// 90 is liblsl's default. With [monotonize], output never goes backwards
  /// (`proc_monotonize`).
  TimestampSmoother(
    double rate, {
    double halftime = 90,
    this.monotonize = false,
  }) : assert(rate > 0),
       _w1 = 1 / rate,
       _lambda = pow(2, -1 / (rate * halftime)).toDouble();

  final bool monotonize;
  final double _lambda;

  // Regression coefficients (intercept, slope) and the inverse covariance.
  double _w0 = 0;
  double _w1;
  double _p00 = 1e10, _p01 = 0, _p11 = 1e10;

  // Timestamps are fitted relative to the first, which keeps the intercept
  // small beside an LSL clock that may read in the millions of seconds.
  double? _baseline;
  double _seen = 0;
  double _last = double.negativeInfinity;

  double smooth(double timestamp) {
    final baseline = _baseline ??= timestamp;
    final value = timestamp - baseline;
    final u = _seen;
    final pi0 = _p00 + u * _p01;
    final pi1 = _p01 + u * _p11;
    final error = value - _w0 - _w1 * u;
    final gain = 1 / (_lambda + pi0 + pi1 * u);
    _p00 = (_p00 - pi0 * pi0 * gain) / _lambda;
    _p01 = (_p01 - pi0 * pi1 * gain) / _lambda;
    _p11 = (_p11 - pi1 * pi1 * gain) / _lambda;
    _w0 += error * (_p00 + _p01 * u);
    _w1 += error * (_p01 + _p11 * u);
    _seen++;
    var out = _w0 + _w1 * u + baseline;
    if (monotonize && out < _last) out = _last;
    return _last = out;
  }

  /// Smooths [timestamps] in place.
  void smoothAll(Float64List timestamps) {
    for (var i = 0; i < timestamps.length; i++) {
      timestamps[i] = smooth(timestamps[i]);
    }
  }
}

/// The last few arrival latencies of a stream at one node: their mean and
/// spread, for [ClockHop.latency] and [ClockHop.jitter]. Also used for the
/// times samples waited there, for [ClockHop.held].
final class LatencyWindow {
  LatencyWindow([int size = 256]) : _values = Float64List(size);

  final Float64List _values;
  int _count = 0;
  int _next = 0;

  void add(double latency) {
    if (!latency.isFinite) return;
    _values[_next] = latency;
    _next = (_next + 1) % _values.length;
    if (_count < _values.length) _count++;
  }

  void clear() => _count = _next = 0;

  double? get mean {
    if (_count == 0) return null;
    var sum = 0.0;
    for (var i = 0; i < _count; i++) {
      sum += _values[i];
    }
    return sum / _count;
  }

  /// Standard deviation of what is held, or null when empty.
  double? get jitter {
    final m = mean;
    if (m == null) return null;
    var sum = 0.0;
    for (var i = 0; i < _count; i++) {
      final d = _values[i] - m;
      sum += d * d;
    }
    return sqrt(sum / _count);
  }
}
