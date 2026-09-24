import 'dart:math' as math;

/// Fraction of a lane an auto-scaled trace may use on each side.
const laneFill = 0.45;

/// An auto scale changes only when the data asks for this factor more or
/// less.
const settleFactor = 1.5;

const _steps = [1.0, 2.0, 5.0];

double _round12(double v) => double.parse(v.toStringAsPrecision(12));

/// The smallest value of the 1-2-5 series (…, 0.5, 1, 2, 5, 10, …) at or
/// above [value].
double niceScale(double value) {
  if (!(value > 0) || !value.isFinite) return 1;
  final decade = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
  for (final step in [..._steps, 10.0]) {
    final candidate = step * decade;
    if (candidate >= value * (1 - 1e-9)) return _round12(candidate);
  }
  return _round12(10 * decade);
}

double _seriesValue(int index) {
  final decade = index >= 0 ? index ~/ 3 : -((-index + 2) ~/ 3);
  final step = _steps[index - decade * 3];
  return _round12(step * math.pow(10, decade));
}

/// The next 1-2-5 value above ([direction] > 0) or below [value].
double stepScale(double value, int direction) {
  final nice = niceScale(value);
  final index = (3 * math.log(nice) / math.ln10).round();
  if (direction > 0) {
    return nice > value * (1 + 1e-9) ? nice : _seriesValue(index + 1);
  }
  return _seriesValue(index - 1);
}

/// One scale for all channels, fitting a typical channel (median standard
/// deviation) in its lane.
double? autoScaleShared(List<double> stds) {
  final xs = [
    for (final s in stds)
      if (s.isFinite) s,
  ]..sort();
  if (xs.isEmpty) return null;
  final median = xs.length.isOdd
      ? xs[xs.length ~/ 2]
      : (xs[xs.length ~/ 2 - 1] + xs[xs.length ~/ 2]) / 2;
  final spread = median * 3;
  return spread > 0 ? niceScale(spread / laneFill) : null;
}

/// A scale per channel so each channel's peak deviation fits its lane.
double autoScaleChannel(double peak) =>
    peak > 0 && peak.isFinite ? niceScale(peak / laneFill) : 1;

/// Keep [current] unless [target] differs from it by more than
/// [settleFactor].
double? settle(double? current, double? target) {
  if (target == null) return current;
  if (current == null ||
      !(current / settleFactor <= target && target <= current * settleFactor)) {
    return target;
  }
  return current;
}
