import 'dart:math' as math;

/// Frequency of the ADS1299's AC lead-off current as the board sets it
/// (fCLK / 2^16).
const cytonLeadOffHz = 31.25;

/// The lead-off current: 6 nA.
const cytonLeadOffAmps = 6e-9;

/// The resistor in series with each input: 2.2 kΩ.
const cytonSeriesOhms = 2200.0;

/// Impedance of an electrode from the amplitude (µV, peak) of the lead-off
/// signal on its channel, as the OpenBCI GUI computes it: Ohm's law with
/// the 6 nA current, less the 2.2 kΩ series resistor.
double cytonImpedanceOhms(double amplitudeMicrovolts) => math.max(
  0,
  amplitudeMicrovolts * 1e-6 / cytonLeadOffAmps - cytonSeriesOhms,
);

/// Amplitude (peak) of the [hz] component of [x], sampled at [rate], by
/// the Goertzel algorithm. The mean is removed first. Whole periods of
/// [hz] in [x] avoid leakage: a multiple of 8 samples at 250 Hz, or of 4
/// at 125 Hz, for the lead-off frequency.
double toneAmplitude(
  List<double> x,
  double rate, {
  double hz = cytonLeadOffHz,
}) {
  final n = x.length;
  if (n == 0) return 0;
  var mean = 0.0;
  for (final v in x) {
    mean += v;
  }
  mean /= n;
  final w = 2 * math.pi * hz / rate;
  final c = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (final v in x) {
    final s0 = v - mean + c * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final re = s1 - s2 * math.cos(w);
  final im = s2 * math.sin(w);
  return 2 * math.sqrt(re * re + im * im) / n;
}
