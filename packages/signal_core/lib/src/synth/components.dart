import 'dart:math' as math;
import 'dart:typed_data';

/// Something that happened in a generated signal, e.g. the onset of a
/// blink, at sample [sample] (counted from the generator's start).
class SynthEvent {
  final int sample;
  final String label;

  const SynthEvent(this.sample, this.label);

  @override
  bool operator ==(Object other) =>
      other is SynthEvent && other.sample == sample && other.label == label;

  @override
  int get hashCode => Object.hash(sample, label);

  @override
  String toString() => 'SynthEvent($sample, $label)';
}

/// Where a voice reports events: the sample and a label.
typedef SynthEventSink = void Function(int sample, String label);

/// The generator of one component for one channel, with its state.
abstract class SynthVoice {
  /// Add samples [start, start + n) to `out[offset + i * stride]`.
  void add(
    Float64List out,
    int offset,
    int stride,
    int start,
    int n,
    SynthEventSink? events,
  );
}

/// A part of a channel's signal; a channel is the sum of its components.
///
/// Periodic components are functions of the sample index, so the output
/// does not depend on how it is divided into chunks. Random components
/// draw a fixed number of values per sample for the same reason. Those
/// with a [shared] key draw from a sequence that is the same on every
/// channel, so their events (e.g. blinks) happen on all channels at once,
/// with each channel's amplitude.
abstract class SynthComponent {
  const SynthComponent();

  /// Key of the random sequence shared across channels, or null for one
  /// of the channel's own.
  String? get shared => null;

  /// A voice at [rate] Hz drawing from [random].
  SynthVoice voice(double rate, math.Random random);
}

/// A normally distributed value (Box-Muller), drawing two values.
double _gaussian(math.Random r) {
  final u = 1 - r.nextDouble(); // (0, 1]
  final v = r.nextDouble();
  return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
}

/// A periodic voice: `amplitude * shape(phase)`, phase in cycles.
class _Periodic implements SynthVoice {
  final double rate;
  final double Function(int sample) value;

  _Periodic(this.rate, this.value);

  @override
  void add(
    Float64List out,
    int offset,
    int stride,
    int start,
    int n,
    SynthEventSink? events,
  ) {
    for (var i = 0; i < n; i++) {
      out[offset + i * stride] += value(start + i);
    }
  }
}

/// Phase in cycles of [frequency] Hz at [sample], kept in [0, 1) without
/// losing precision as the sample index grows.
double _cycles(int sample, double frequency, double rate) {
  // frequency / rate cycles per sample; reduce the product modulo 1 in two
  // parts so that large sample counts stay exact.
  final perSample = frequency / rate;
  final whole = sample ~/ 65536, rest = sample % 65536;
  final a = (whole * 65536 * perSample) % 1;
  final b = (rest * perSample) % 1;
  return (a + b) % 1;
}

/// A sine wave.
class Sine extends SynthComponent {
  final double frequency;
  final double amplitude;

  /// Phase at sample 0, in radians.
  final double phase;

  const Sine(this.frequency, this.amplitude, {this.phase = 0});

  @override
  SynthVoice voice(double rate, math.Random random) => _Periodic(
    rate,
    (s) =>
        amplitude * math.sin(2 * math.pi * _cycles(s, frequency, rate) + phase),
  );
}

/// A square wave between ±[amplitude], high for [duty] of each cycle.
class Square extends SynthComponent {
  final double frequency;
  final double amplitude;
  final double duty;

  const Square(this.frequency, this.amplitude, {this.duty = 0.5});

  @override
  SynthVoice voice(double rate, math.Random random) => _Periodic(
    rate,
    (s) => _cycles(s, frequency, rate) < duty ? amplitude : -amplitude,
  );
}

/// A sawtooth rising from -[amplitude] to [amplitude] over each cycle.
class Sawtooth extends SynthComponent {
  final double frequency;
  final double amplitude;

  const Sawtooth(this.frequency, this.amplitude);

  @override
  SynthVoice voice(double rate, math.Random random) =>
      _Periodic(rate, (s) => amplitude * (2 * _cycles(s, frequency, rate) - 1));
}

/// A sine sweeping linearly from [from] to [to] Hz over [period] seconds,
/// then starting again.
class Chirp extends SynthComponent {
  final double from;
  final double to;
  final double period;
  final double amplitude;

  const Chirp(this.from, this.to, this.period, this.amplitude);

  @override
  SynthVoice voice(double rate, math.Random random) {
    final length = math.max(1, (period * rate).round());
    final k = (to - from) / (length / rate);
    return _Periodic(rate, (s) {
      final t = (s % length) / rate;
      final cycles = from * t + k * t * t / 2;
      return amplitude * math.sin(2 * math.pi * (cycles % 1));
    });
  }
}

/// A constant offset.
class Dc extends SynthComponent {
  final double value;

  const Dc(this.value);

  @override
  SynthVoice voice(double rate, math.Random random) =>
      _Periodic(rate, (_) => value);
}

/// A single-sample pulse of [amplitude] every [interval] seconds, reported
/// as an event `impulse`.
class ImpulseTrain extends SynthComponent {
  final double interval;
  final double amplitude;

  const ImpulseTrain(this.interval, this.amplitude);

  @override
  SynthVoice voice(double rate, math.Random random) =>
      _ImpulseVoice(math.max(1, (interval * rate).round()), amplitude);
}

class _ImpulseVoice implements SynthVoice {
  final int every;
  final double amplitude;

  _ImpulseVoice(this.every, this.amplitude);

  @override
  void add(
    Float64List out,
    int offset,
    int stride,
    int start,
    int n,
    SynthEventSink? events,
  ) {
    for (var i = 0; i < n; i++) {
      if ((start + i) % every == 0) {
        out[offset + i * stride] += amplitude;
        events?.call(start + i, 'impulse');
      }
    }
  }
}

/// A voice that draws from its random sequence once per sample.
abstract class _RandomVoice implements SynthVoice {
  final math.Random random;

  _RandomVoice(this.random);

  double next();

  @override
  void add(
    Float64List out,
    int offset,
    int stride,
    int start,
    int n,
    SynthEventSink? events,
  ) {
    for (var i = 0; i < n; i++) {
      out[offset + i * stride] += next();
    }
  }
}

/// Gaussian white noise with standard deviation [rms].
class WhiteNoise extends SynthComponent {
  final double rms;

  const WhiteNoise(this.rms);

  @override
  SynthVoice voice(double rate, math.Random random) => _WhiteVoice(random, rms);
}

class _WhiteVoice extends _RandomVoice {
  final double rms;
  _WhiteVoice(super.random, this.rms);

  @override
  double next() => rms * _gaussian(random);
}

/// Pink (1/f) noise with standard deviation about [rms], from white noise
/// through Paul Kellet's filter.
class PinkNoise extends SynthComponent {
  final double rms;

  const PinkNoise(this.rms);

  @override
  SynthVoice voice(double rate, math.Random random) => _PinkVoice(random, rms);
}

class _PinkVoice extends _RandomVoice {
  /// The filter's output standard deviation for unit white noise.
  static const _gain = 2.98;

  final double scale;
  double b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;

  _PinkVoice(super.random, double rms) : scale = rms / _gain {
    // Settle the slowest stage, so the noise starts at its usual level.
    for (var i = 0; i < 2000; i++) {
      _step(_gaussian(random));
    }
  }

  double _step(double w) {
    b0 = 0.99886 * b0 + w * 0.0555179;
    b1 = 0.99332 * b1 + w * 0.0750759;
    b2 = 0.96900 * b2 + w * 0.1538520;
    b3 = 0.86650 * b3 + w * 0.3104856;
    b4 = 0.55000 * b4 + w * 0.5329522;
    b5 = -0.7616 * b5 - w * 0.0168980;
    final pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
    b6 = w * 0.115926;
    return pink;
  }

  @override
  double next() => scale * _step(_gaussian(random));
}

/// Mains interference: a sine at [frequency] Hz (50 or 60) and its
/// [harmonics] below the Nyquist frequency, the k-th at amplitude / k.
class LineNoise extends SynthComponent {
  final double frequency;
  final double amplitude;
  final int harmonics;

  const LineNoise(this.amplitude, {this.frequency = 50, this.harmonics = 1});

  @override
  SynthVoice voice(double rate, math.Random random) {
    final ks = [
      for (var k = 1; k <= harmonics; k++)
        if (k * frequency < rate / 2) k,
    ];
    return _Periodic(rate, (s) {
      var v = 0.0;
      for (final k in ks) {
        v +=
            amplitude /
            k *
            math.sin(2 * math.pi * _cycles(s, k * frequency, rate));
      }
      return v;
    });
  }
}

/// Slow baseline wander: an Ornstein-Uhlenbeck process with standard
/// deviation [rms] and time constant [timescale] seconds.
class Drift extends SynthComponent {
  final double rms;
  final double timescale;

  const Drift(this.rms, {this.timescale = 10});

  @override
  SynthVoice voice(double rate, math.Random random) =>
      _DriftVoice(random, rms, timescale, rate);
}

class _DriftVoice extends _RandomVoice {
  final double decay, step;
  double x = 0;

  _DriftVoice(super.random, double rms, double timescale, double rate)
    : decay = math.exp(-1 / (timescale * rate)),
      step = rms * math.sqrt(1 - math.exp(-2 / (timescale * rate)));

  @override
  double next() => x = decay * x + step * _gaussian(random);
}

/// A shape of [length] samples added at random onsets, about [perSecond]
/// times a second, never overlapping; each onset is reported as [label].
abstract class _TransientVoice implements SynthVoice {
  final math.Random random;
  final double chance;
  final int length;
  final String label;
  final double amplitude;

  /// Sample in the current transient, or -1 between them.
  int _at = -1;
  int _sign = 1;

  _TransientVoice(
    this.random,
    double perSecond,
    double rate,
    double seconds,
    this.label,
    this.amplitude,
  ) : chance = perSecond / rate,
      length = math.max(1, (seconds * rate).round());

  /// The shape at [x] in [0, 1).
  double shape(double x);

  /// Whether onsets alternate in sign.
  bool get bipolar => false;

  @override
  void add(
    Float64List out,
    int offset,
    int stride,
    int start,
    int n,
    SynthEventSink? events,
  ) {
    for (var i = 0; i < n; i++) {
      final u = random.nextDouble();
      final flip = random.nextDouble();
      if (_at < 0 && u < chance) {
        _at = 0;
        _sign = bipolar && flip < 0.5 ? -1 : 1;
        events?.call(start + i, label);
      }
      if (_at >= 0) {
        out[offset + i * stride] += _sign * amplitude * shape(_at / length);
        if (++_at >= length) _at = -1;
      }
    }
  }
}

/// Sharp transients (e.g. electrode pops), about [perSecond] a second,
/// each [width] seconds; reported as `spike`. Each channel has its own.
class Spikes extends SynthComponent {
  final double perSecond;
  final double amplitude;
  final double width;

  const Spikes(this.perSecond, this.amplitude, {this.width = 0.03});

  @override
  SynthVoice voice(double rate, math.Random random) =>
      _SpikeVoice(random, perSecond, rate, width, amplitude);
}

class _SpikeVoice extends _TransientVoice {
  _SpikeVoice(math.Random r, double p, double rate, double w, double a)
    : super(r, p, rate, w, 'spike', a);

  @override
  bool get bipolar => true;

  // A fast rise and a slower fall.
  @override
  double shape(double x) => x < 0.2 ? x / 0.2 : (1 - x) / 0.8;
}

/// Eye blinks: smooth bumps of [duration] seconds, about [perMinute] a
/// minute, at the same moments on every channel ([shared]); reported as
/// `blink`. Give frontal channels the larger [amplitude].
class Blinks extends SynthComponent {
  final double perMinute;
  final double amplitude;
  final double duration;

  const Blinks(this.amplitude, {this.perMinute = 15, this.duration = 0.3});

  @override
  String get shared => 'blinks';

  @override
  SynthVoice voice(double rate, math.Random random) =>
      _BlinkVoice(random, perMinute / 60, rate, duration, amplitude);
}

class _BlinkVoice extends _TransientVoice {
  _BlinkVoice(math.Random r, double p, double rate, double d, double a)
    : super(r, p, rate, d, 'blink', a);

  @override
  double shape(double x) {
    final s = math.sin(math.pi * x);
    return s * s;
  }
}

/// Bursts of alpha rhythm at [frequency] Hz: on for about [burst] seconds,
/// off for about [gap], fading in and out over [ramp] seconds, at the same
/// moments on every channel ([shared]). Each onset is reported as `alpha`.
class AlphaBursts extends SynthComponent {
  final double frequency;
  final double amplitude;
  final double burst;
  final double gap;
  final double ramp;

  const AlphaBursts(
    this.amplitude, {
    this.frequency = 10,
    this.burst = 1.5,
    this.gap = 2,
    this.ramp = 0.2,
  });

  @override
  String get shared => 'alpha';

  @override
  SynthVoice voice(double rate, math.Random random) =>
      _AlphaVoice(random, this, rate);
}

class _AlphaVoice implements SynthVoice {
  final math.Random random;
  final AlphaBursts c;
  final double rate;
  final double toOn, toOff, slew;
  bool on = false;
  double level = 0;

  _AlphaVoice(this.random, this.c, this.rate)
    : toOn = 1 / (c.gap * rate),
      toOff = 1 / (c.burst * rate),
      slew = 1 / math.max(1, c.ramp * rate);

  @override
  void add(
    Float64List out,
    int offset,
    int stride,
    int start,
    int n,
    SynthEventSink? events,
  ) {
    for (var i = 0; i < n; i++) {
      final s = start + i;
      final u = random.nextDouble();
      if (on ? u < toOff : u < toOn) {
        on = !on;
        if (on) events?.call(s, 'alpha');
      }
      level = on ? math.min(1, level + slew) : math.max(0, level - slew);
      if (level > 0) {
        final env = 0.5 - 0.5 * math.cos(math.pi * level);
        out[offset + i * stride] +=
            env *
            c.amplitude *
            math.sin(2 * math.pi * _cycles(s, c.frequency, rate));
      }
    }
  }
}
