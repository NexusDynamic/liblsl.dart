import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Signal power for colouring traces. Every metric is an amplitude in the
/// signal's own unit: RMS after removing the mean, or for a band the square
/// root of the Welch power spectral density summed over that band (the RMS
/// of the signal within the band).
const bands = <String, (double, double)>{
  'delta': (1, 4),
  'theta': (4, 8),
  'alpha': (8, 13),
  'beta': (13, 30),
  'gamma': (30, 45),
};

const metrics = ['rms', 'delta', 'theta', 'alpha', 'beta', 'gamma'];

String metricLabel(String metric) {
  if (metric == 'rms') return 'RMS';
  final (lo, hi) = bands[metric]!;
  const symbols = {
    'delta': 'δ',
    'theta': 'θ',
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
  };
  return '${symbols[metric]} $metric ${_g(lo)}–${_g(hi)} Hz';
}

String _g(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

const minBinS = 0.5;

/// Band power needs the raw samples, which is only done for windows up to
/// this long.
const maxBandWindowS = 600.0;

/// Heatmap bin length: at least two cycles of a band's lowest frequency.
double binLength(String metric) {
  final band = bands[metric];
  if (band == null) return minBinS;
  return math.max(minBinS, 2 / band.$1);
}

/// Heatmap bins for a window: [binLength], but no more than about
/// [maxBins] over the window, rounded to a 1-2-5 value so bins stay put
/// while scrolling.
double heatmapBin(String metric, double windowS, {int maxBins = 400}) {
  var bin = binLength(metric);
  final min = windowS / maxBins;
  if (bin < min) {
    for (final step in _series) {
      if (step >= min) {
        bin = step;
        break;
      }
    }
  }
  return bin;
}

final _series = [
  for (var e = -1; e <= 5; e++)
    for (final s in [1.0, 2.0, 5.0]) s * math.pow(10, e),
];

/// Power of a band in [x] sampled at [rate] Hz (Welch, Hann window,
/// segments of up to two seconds with 50% overlap, like SciPy's defaults).
/// NaN if it cannot be computed.
double bandPower(List<double> x, double rate, String metric) {
  final band = bands[metric];
  if (band == null) return _std(x);
  final (lo, hi) = band;
  final n = x.length;
  if (n < 4 || rate <= 0 || hi >= rate / 2) return double.nan;
  final seg = math.min(n, (rate * 2).floor());
  final step = seg ~/ 2;
  final window = Float64List(seg);
  var windowSq = 0.0;
  for (var i = 0; i < seg; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / seg);
    windowSq += window[i] * window[i];
  }
  final dft = _RealDft(seg);
  final df = rate / seg;
  final kLo = (lo / df).ceil();
  final kHi = math.min((hi / df).ceil() - 1, seg ~/ 2);
  if (kHi < kLo) return double.nan;
  final psd = Float64List(kHi - kLo + 1);
  final buf = Float64List(seg);
  var count = 0;
  for (var start = 0; start + seg <= n; start += step == 0 ? seg : step) {
    var mean = 0.0;
    for (var i = 0; i < seg; i++) {
      mean += x[start + i];
    }
    mean /= seg;
    for (var i = 0; i < seg; i++) {
      buf[i] = (x[start + i] - mean) * window[i];
    }
    final spectrum = dft(buf);
    for (var k = kLo; k <= kHi; k++) {
      final c = spectrum[k];
      var p = (c.x * c.x + c.y * c.y) / (rate * windowSq);
      if (k != 0 && !(seg.isEven && k == seg ~/ 2)) p *= 2;
      psd[k - kLo] += p;
    }
    count++;
  }
  if (count == 0) return double.nan;
  var sum = 0.0;
  for (final p in psd) {
    sum += p / count;
  }
  return math.sqrt(sum * df);
}

double _std(List<double> x) {
  var n = 0;
  var mean = 0.0;
  for (final v in x) {
    if (v.isNaN) continue;
    n++;
    mean += v;
  }
  if (n < 2) return double.nan;
  mean /= n;
  var ss = 0.0;
  for (final v in x) {
    if (v.isNaN) continue;
    ss += (v - mean) * (v - mean);
  }
  return math.sqrt(ss / n);
}

/// Band power in consecutive bins of [binS] seconds aligned on multiples
/// of [binS]: `(first bin start, values per channel)`. A bin with less than
/// half its samples gives NaN.
(double, List<Float64List>) binnedBandPower(
  List<Float32List> channels,
  double start,
  double rate,
  String metric,
  double binS,
) {
  final n = channels.isEmpty ? 0 : channels.first.length;
  if (n == 0) return (start, const []);
  final first = (start / binS).floor() * binS;
  final end = start + n / rate;
  final count = ((end - first) / binS).ceil();
  final out = [
    for (final _ in channels)
      Float64List(count)..fillRange(0, count, double.nan),
  ];
  final needed = math.max(4, 0.5 * binS * rate);
  for (var b = 0; b < count; b++) {
    final i0 = math.max(0, ((first + b * binS - start) * rate).ceil());
    final i1 = math.min(n, ((first + (b + 1) * binS - start) * rate).ceil());
    if (i1 - i0 < needed) continue;
    for (var c = 0; c < channels.length; c++) {
      out[c][b] = bandPower(
        Float64List.fromList(channels[c].sublist(i0, i1)),
        rate,
        metric,
      );
    }
  }
  return (first, out);
}

/// The 2nd and 98th percentiles of the finite values, for colour levels.
(double, double)? percentileLevels(Iterable<double> values) {
  final xs = [
    for (final v in values)
      if (v.isFinite) v,
  ]..sort();
  if (xs.isEmpty) return null;
  double pct(double p) {
    final pos = p / 100 * (xs.length - 1);
    final i = pos.floor();
    final f = pos - i;
    return i + 1 < xs.length ? xs[i] * (1 - f) + xs[i + 1] * f : xs[i];
  }

  final lo = pct(2), hi = pct(98);
  return (lo, hi > lo ? hi : lo + math.max(lo.abs(), 1e-12));
}

/// The DFT of real signals of one length. fftea handles lengths that are not
/// a power of two (two seconds at 500 Hz is 1000 samples) with CompositeFFT,
/// which allocates a Uint64List and so throws on the web; those lengths go
/// through Bluestein's algorithm on a power-of-two FFT instead.
class _RealDft {
  final FFT _fft;

  /// exp(-iπk²/n), or null for a power-of-two length.
  final Float64x2List? _chirp;

  /// The FFT of the conjugate chirp, wrapped around to the padded length.
  final Float64x2List? _kernel;
  final Float64x2List? _buf;

  _RealDft._(this._fft, this._chirp, this._kernel, this._buf);

  factory _RealDft(int n) {
    if (n & (n - 1) == 0) return _RealDft._(FFT(n), null, null, null);
    var m = 1;
    while (m < 2 * n - 1) {
      m <<= 1;
    }
    final chirp = Float64x2List(n);
    for (var k = 0; k < n; k++) {
      // k² mod 2n keeps the angle small, so it stays exact for long segments.
      final a = math.pi * ((k * k) % (2 * n)) / n;
      chirp[k] = Float64x2(math.cos(a), -math.sin(a));
    }
    final kernel = Float64x2List(m);
    kernel[0] = Float64x2(1, 0);
    for (var k = 1; k < n; k++) {
      kernel[k] = kernel[m - k] = Float64x2(chirp[k].x, -chirp[k].y);
    }
    final fft = FFT(m)..inPlaceFft(kernel);
    return _RealDft._(fft, chirp, kernel, Float64x2List(m));
  }

  /// The spectrum of [x]; bins up to half the length are meaningful.
  Float64x2List call(Float64List x) {
    final chirp = _chirp;
    if (chirp == null) return _fft.realFft(x);
    final kernel = _kernel!, a = _buf!;
    final n = chirp.length;
    for (var k = 0; k < n; k++) {
      a[k] = chirp[k] * Float64x2.splat(x[k]);
    }
    a.fillRange(n, a.length, Float64x2.zero());
    _fft.inPlaceFft(a);
    for (var k = 0; k < a.length; k++) {
      a[k] = _mul(a[k], kernel[k]);
    }
    _fft.inPlaceInverseFft(a);
    for (var k = 0; k < n; k++) {
      a[k] = _mul(a[k], chirp[k]);
    }
    return Float64x2List.sublistView(a, 0, n);
  }

  static Float64x2 _mul(Float64x2 p, Float64x2 q) =>
      Float64x2(p.x * q.x - p.y * q.y, p.x * q.y + p.y * q.x);
}
