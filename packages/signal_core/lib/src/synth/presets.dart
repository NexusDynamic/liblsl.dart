import 'dart:math' as math;

import 'components.dart';
import 'generator.dart';

/// Ready-made test signals.
enum SynthPreset {
  /// Sines (channel n at n × the frequency, wrapping below the Nyquist
  /// frequency) and white noise.
  sines('Sines', 'Sine waves, channel n at n × the frequency, with noise.'),

  /// Each channel a different waveform, for checking scales and view
  /// options.
  testPattern(
    'Test pattern',
    'A different waveform on each channel: sine, square, sawtooth, chirp, '
        'DC, impulses, white and pink noise, line noise.',
  ),

  /// Background EEG: 1/f noise, alpha bursts strongest at the back, a
  /// little line noise.
  eegResting(
    'EEG, resting',
    'Pink noise, alpha bursts (strongest at the back) and a little line '
        'noise.',
  ),

  /// Resting EEG with artefacts: blinks (strongest at the front), spikes,
  /// drift, a channel that clips and one that is flat.
  eegArtefacts(
    'EEG with artefacts',
    'Resting EEG with blinks, spikes and drift; one channel clips and one '
        'is flat.',
  ),

  /// A slow sine under strong line noise and its harmonics, for the notch
  /// filter.
  lineNoise(
    'Line noise',
    'A slow sine under strong line noise and its harmonics.',
  ),

  /// Cheap to make: a sine and noise per channel, for many channels at
  /// high rates.
  stress(
    'Stress',
    'A sine and noise per channel, cheap to make: for many channels at '
        'high rates.',
  );

  final String label;
  final String description;

  const SynthPreset(this.label, this.description);

  /// The preset called [name] (as in [SynthPreset.name]), or null.
  static SynthPreset? byName(String name) {
    for (final p in values) {
      if (p.name.toLowerCase() == name.toLowerCase()) return p;
    }
    return null;
  }
}

/// 10-20 electrode names from front to back, for EEG-like presets with up
/// to this many channels.
const eegLabels = [
  'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'T7', 'C3', 'Cz', //
  'C4', 'T8', 'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2',
];

/// What to generate: a [preset] at [channels] × [rate] Hz, with the
/// preset's sizes scaled by [amplitude] (microvolts).
class SynthSpec {
  final SynthPreset preset;
  final int channels;
  final double rate;

  /// Base frequency of [SynthPreset.sines], [SynthPreset.testPattern] and
  /// [SynthPreset.stress].
  final double frequency;

  /// Peak of a sine, roughly the size of the signal.
  final double amplitude;

  /// Size of the white noise of [SynthPreset.sines] (as the ± range of
  /// uniform noise, for compatibility).
  final double noise;

  /// Mains frequency, 50 or 60 Hz.
  final double lineFrequency;

  final int seed;

  const SynthSpec({
    this.preset = SynthPreset.sines,
    this.channels = 8,
    this.rate = 250,
    this.frequency = 10,
    this.amplitude = 50,
    this.noise = 5,
    this.lineFrequency = 50,
    this.seed = 0,
  }) : assert(channels > 0),
       assert(rate > 0);

  /// A generator of this signal, from its start.
  SignalGenerator generator() =>
      SignalGenerator(rate: rate, channels: recipes(), seed: seed);

  /// Each channel's recipe.
  List<ChannelRecipe> recipes() => switch (preset) {
    SynthPreset.sines => _sines(),
    SynthPreset.testPattern => _testPattern(),
    SynthPreset.eegResting => _eeg(artefacts: false),
    SynthPreset.eegArtefacts => _eeg(artefacts: true),
    SynthPreset.lineNoise => _lineNoise(),
    SynthPreset.stress => _stress(),
  };

  String _ch(int c) => 'ch${c + 1}';

  /// Multiples of [frequency] below 0.45 × rate, cycling, so that many
  /// channels do not alias.
  double _harmonic(int c) {
    final k = math.max(1, (0.45 * rate / frequency).floor());
    return frequency * (c % k + 1);
  }

  List<ChannelRecipe> _sines() => [
    for (var c = 0; c < channels; c++)
      ChannelRecipe(_ch(c), [
        Sine(_harmonic(c), amplitude),
        // Uniform noise of ±noise has this standard deviation.
        if (noise > 0) WhiteNoise(noise / math.sqrt(3)),
      ]),
  ];

  List<ChannelRecipe> _testPattern() {
    final a = amplitude, f = frequency;
    final nyquist = rate / 2;
    final patterns = <(String, List<SynthComponent>)>[
      ('sine', [Sine(f, a)]),
      ('square', [Square(f, a)]),
      ('sawtooth', [Sawtooth(f, a)]),
      ('chirp', [Chirp(1, 0.8 * nyquist, 10, a)]),
      ('dc', [Dc(a)]),
      ('impulses', [ImpulseTrain(1, a)]),
      ('white', [WhiteNoise(a / 3)]),
      ('pink', [PinkNoise(a / 3)]),
      ('line', [LineNoise(a, frequency: lineFrequency, harmonics: 3)]),
    ];
    return [
      for (var c = 0; c < channels; c++)
        ChannelRecipe(
          '${_ch(c)} ${patterns[c % patterns.length].$1}',
          patterns[c % patterns.length].$2,
        ),
    ];
  }

  List<ChannelRecipe> _eeg({required bool artefacts}) {
    final a = amplitude;
    final n = channels;
    // 0 at the front, 1 at the back.
    double back(int c) => n == 1 ? 1 : c / (n - 1);
    final flat = artefacts && n >= 3 ? n - 1 : -1;
    final clipped = artefacts && n >= 4 ? n - 2 : -1;
    return [
      for (var c = 0; c < n; c++)
        if (c == flat)
          ChannelRecipe.flat('${_label(c)} (flat)')
        else
          ChannelRecipe(c == clipped ? '${_label(c)} (clips)' : _label(c), [
            PinkNoise(0.4 * a),
            AlphaBursts((0.2 + 0.8 * back(c)) * a),
            LineNoise(0.05 * a, frequency: lineFrequency),
            WhiteNoise(0.05 * a),
            if (artefacts) ...[
              Blinks(3 * a * math.pow(1 - back(c), 2)),
              Spikes(0.1, 3 * a),
              Drift(0.5 * a, timescale: 20),
            ],
            if (c == clipped) Drift(2 * a, timescale: 5),
          ], clip: c == clipped ? 1.2 * a : null),
    ];
  }

  String _label(int c) => channels <= eegLabels.length
      ? eegLabels[(c * eegLabels.length / channels).floor()]
      : _ch(c);

  List<ChannelRecipe> _lineNoise() => [
    for (var c = 0; c < channels; c++)
      ChannelRecipe(_ch(c), [
        Sine(2 + c % 4, 0.5 * amplitude),
        LineNoise(amplitude, frequency: lineFrequency, harmonics: 3),
        WhiteNoise(0.05 * amplitude),
      ]),
  ];

  List<ChannelRecipe> _stress() => [
    for (var c = 0; c < channels; c++)
      ChannelRecipe(_ch(c), [
        Sine(_harmonic(c % 8), amplitude),
        WhiteNoise(0.2 * amplitude),
      ]),
  ];

  SynthSpec copyWith({
    SynthPreset? preset,
    int? channels,
    double? rate,
    double? frequency,
    double? amplitude,
    double? noise,
    double? lineFrequency,
    int? seed,
  }) => SynthSpec(
    preset: preset ?? this.preset,
    channels: channels ?? this.channels,
    rate: rate ?? this.rate,
    frequency: frequency ?? this.frequency,
    amplitude: amplitude ?? this.amplitude,
    noise: noise ?? this.noise,
    lineFrequency: lineFrequency ?? this.lineFrequency,
    seed: seed ?? this.seed,
  );

  @override
  String toString() => '${preset.label}, $channels ch at ${_n(rate)} Hz';

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
