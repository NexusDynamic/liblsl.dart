import 'dart:math' as math;
import 'dart:typed_data';

import '../requests.dart';

/// A cascade of second-order IIR sections (biquads), as in SciPy's `sos`
/// format: each section is `b0 b1 b2 a0 a1 a2`, with `a0 == 1`.
class Sos {
  /// Six coefficients per section.
  final Float64List coefficients;

  Sos(this.coefficients) {
    if (coefficients.length % 6 != 0) {
      throw ArgumentError.value(coefficients, 'coefficients', 'not 6 per row');
    }
  }

  /// No sections: filtering leaves the signal unchanged.
  Sos.empty() : coefficients = Float64List(0);

  int get sections => coefficients.length ~/ 6;

  bool get isEmpty => coefficients.isEmpty;

  /// A 2nd-order Butterworth high-pass at [cutoff] Hz (SciPy
  /// `butter(2, cutoff, 'highpass', fs=fs, output='sos')`).
  factory Sos.butterHighpass(double cutoff, double fs) {
    // Bilinear transform with pre-warping; identical to the RBJ high-pass
    // with Q = 1/sqrt(2).
    final w0 = 2 * math.pi * cutoff / fs;
    final cosW = math.cos(w0);
    final alpha = math.sin(w0) / (2 * math.sqrt1_2);
    final a0 = 1 + alpha;
    final b0 = (1 + cosW) / 2 / a0;
    return Sos(
      Float64List.fromList([
        b0,
        -2 * b0,
        b0,
        1,
        -2 * cosW / a0,
        (1 - alpha) / a0,
      ]),
    );
  }

  /// A notch at [freq] Hz with quality factor [q] (SciPy
  /// `iirnotch(freq, q, fs=fs)`).
  factory Sos.notch(double freq, double fs, {double q = 30}) {
    final w0 = 2 * math.pi * freq / fs;
    final bw = w0 / q;
    // gb = 1/sqrt(2), so sqrt(1 - gb^2) / gb = 1.
    final beta = math.tan(bw / 2);
    final gain = 1 / (1 + beta);
    final c = -2 * math.cos(w0);
    return Sos(
      Float64List.fromList([gain, gain * c, gain, 1, gain * c, 2 * gain - 1]),
    );
  }

  /// The high-pass and notch filters used for display: either may be null
  /// or out of range (0 or at/above Nyquist) to leave it out.
  factory Sos.display(double fs, {double? highpass, double? notch}) {
    final nyquist = fs / 2;
    final parts = <Sos>[
      if (highpass != null && highpass > 0 && highpass < nyquist)
        Sos.butterHighpass(highpass, fs),
      if (notch != null && notch > 0 && notch < nyquist) Sos.notch(notch, fs),
    ];
    return Sos.cascade(parts);
  }

  /// All sections of [parts], in order.
  factory Sos.cascade(List<Sos> parts) {
    final n = parts.fold<int>(0, (s, p) => s + p.coefficients.length);
    final out = Float64List(n);
    var o = 0;
    for (final p in parts) {
      out.setRange(o, o + p.coefficients.length, p.coefficients);
      o += p.coefficients.length;
    }
    return Sos(out);
  }

  /// Initial state for a unit step response in steady state (SciPy
  /// `sosfilt_zi`): two values per section. Multiply by the first sample to
  /// start without a transient.
  Float64List steadyState() {
    final zi = Float64List(sections * 2);
    var scale = 1.0;
    for (var s = 0; s < sections; s++) {
      final o = s * 6;
      final b0 = coefficients[o], b1 = coefficients[o + 1];
      final b2 = coefficients[o + 2];
      final a1 = coefficients[o + 4], a2 = coefficients[o + 5];
      // lfilter_zi: solve (I - A^T) zi = B, with the companion matrix of a.
      final r1 = b1 - a1 * b0;
      final r2 = b2 - a2 * b0;
      // [[1 + a1, -1], [a2, 1]] zi = [r1, r2]
      final det = (1 + a1) + a2;
      final z0 = (r1 + r2) / det;
      final z1 = r2 - a2 * z0;
      zi[s * 2] = scale * z0;
      zi[s * 2 + 1] = scale * z1;
      final sumB = b0 + b1 + b2;
      final sumA = 1 + a1 + a2;
      scale *= sumB / sumA;
    }
    return zi;
  }

  /// Filter [x] in place from [from] to [to] (exclusive), in direct form II
  /// transposed with state [zi] (updated), running backwards when
  /// [reverse] is set.
  void apply(
    List<double> x,
    Float64List zi, {
    int from = 0,
    int? to,
    bool reverse = false,
  }) {
    to ??= x.length;
    final c = coefficients;
    for (var s = 0; s < sections; s++) {
      final o = s * 6;
      final b0 = c[o], b1 = c[o + 1], b2 = c[o + 2];
      final a1 = c[o + 4], a2 = c[o + 5];
      var z0 = zi[s * 2];
      var z1 = zi[s * 2 + 1];
      if (!reverse) {
        for (var i = from; i < to; i++) {
          final xi = x[i];
          final y = b0 * xi + z0;
          z0 = b1 * xi - a1 * y + z1;
          z1 = b2 * xi - a2 * y;
          x[i] = y;
        }
      } else {
        for (var i = to - 1; i >= from; i--) {
          final xi = x[i];
          final y = b0 * xi + z0;
          z0 = b1 * xi - a1 * y + z1;
          z1 = b2 * xi - a2 * y;
          x[i] = y;
        }
      }
      zi[s * 2] = z0;
      zi[s * 2 + 1] = z1;
    }
  }

  /// Zero-phase filtering of [x] in place (SciPy `sosfiltfilt` with odd
  /// extension of [padLength] samples at each end; by default like the
  /// Python viewer, `3 * (2 * sections + 1) * 10`).
  void filtfilt(List<double> x, {int? padLength}) {
    final n = x.length;
    if (isEmpty || n < 2) return;
    final edge = math.min(n - 1, padLength ?? 3 * (2 * sections + 1) * 10);
    final ext = Float64List(n + 2 * edge);
    final first = x[0], last = x[n - 1];
    for (var i = 0; i < edge; i++) {
      ext[i] = 2 * first - x[edge - i];
      ext[edge + n + i] = 2 * last - x[n - 2 - i];
    }
    for (var i = 0; i < n; i++) {
      ext[edge + i] = x[i];
    }
    final zi0 = steadyState();
    final zi = Float64List(zi0.length);
    for (var i = 0; i < zi.length; i++) {
      zi[i] = zi0[i] * ext[0];
    }
    apply(ext, zi);
    final end = ext[ext.length - 1];
    for (var i = 0; i < zi.length; i++) {
      zi[i] = zi0[i] * end;
    }
    apply(ext, zi, reverse: true);
    for (var i = 0; i < n; i++) {
      x[i] = ext[edge + i];
    }
  }
}

/// Causal filtering of a multi-channel stream whose state carries across
/// calls, e.g. for live data. Starts in steady state for the first sample
/// of each channel, so there is no large DC transient.
class SosStreamFilter {
  final Sos sos;
  final int channelCount;
  final Float64List _zi0;
  final List<Float64List?> _state;

  SosStreamFilter(this.sos, this.channelCount)
    : _zi0 = sos.steadyState(),
      _state = List.filled(channelCount, null);

  bool get active => !sos.isEmpty;

  /// Forget the state of [channel], or of all channels; the next sample
  /// starts in steady state again.
  void reset([int? channel]) {
    if (channel != null) {
      _state[channel] = null;
    } else {
      _state.fillRange(0, channelCount, null);
    }
  }

  /// Filter [x] of [channel] in place.
  void process(int channel, List<double> x, {int from = 0, int? to}) {
    if (sos.isEmpty) return;
    to ??= x.length;
    if (from >= to) return;
    var zi = _state[channel];
    if (zi == null) {
      zi = _state[channel] = Float64List(_zi0.length);
      final x0 = x[from];
      for (var i = 0; i < zi.length; i++) {
        zi[i] = _zi0[i] * x0;
      }
    }
    sos.apply(x, zi, from: from, to: to);
  }
}

/// Re-reference [columns] (one list per channel, all the same length) to
/// the mean of the channels not in [exclude], in place. Excluded channels
/// are re-referenced too; they only do not contribute to the mean. NaN
/// values are left out of the mean.
void averageReference(
  List<List<double>> columns, {
  Set<int> exclude = const {},
}) => referenceTo(columns, [
  for (var c = 0; c < columns.length; c++)
    if (!exclude.contains(c)) c,
]);

/// Re-reference [columns] to the mean of [channels], in place, from sample
/// [from] to [to] (exclusive). Every channel is re-referenced, including
/// those in [channels]. NaN values are left out of the mean.
void referenceTo(
  List<List<double>> columns,
  List<int> channels, {
  int from = 0,
  int? to,
}) {
  if (columns.isEmpty) return;
  final ref = [
    for (final c in channels)
      if (c >= 0 && c < columns.length) c,
  ];
  if (ref.isEmpty) return;
  to ??= columns.first.length;
  for (var i = from; i < to; i++) {
    var sum = 0.0;
    var count = 0;
    for (final c in ref) {
      final v = columns[c][i];
      if (v.isNaN) continue;
      sum += v;
      count++;
    }
    if (count == 0) continue;
    final m = sum / count;
    for (final col in columns) {
      col[i] -= m;
    }
  }
}

/// Apply the referencing of [spec] to [columns] in place, over samples
/// [from] to [to] (exclusive).
void applyReference(
  List<List<double>> columns,
  DerivedSpec spec, {
  int from = 0,
  int? to,
}) {
  if (spec.averageReference) {
    referenceTo(
      columns,
      [
        for (var c = 0; c < columns.length; c++)
          if (!spec.exclude.contains(c)) c,
      ],
      from: from,
      to: to,
    );
  } else if (spec.referenceOf != null) {
    referenceTo(columns, spec.referenceOf!, from: from, to: to);
  }
}
