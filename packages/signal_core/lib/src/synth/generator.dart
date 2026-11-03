import 'dart:math' as math;
import 'dart:typed_data';

import 'components.dart';

/// How one channel of a [SignalGenerator] is made: the sum of its
/// [components], limited to ±[clip] if given.
class ChannelRecipe {
  final String label;
  final String unit;
  final List<SynthComponent> components;

  /// Values beyond ±clip are held at it, as by an amplifier that saturates.
  final double? clip;

  const ChannelRecipe(
    this.label,
    this.components, {
    this.unit = 'microvolts',
    this.clip,
  });

  /// A dead channel: [value] throughout.
  ChannelRecipe.flat(this.label, {double value = 0, this.unit = 'microvolts'})
    : components = [if (value != 0) Dc(value)],
      clip = null;
}

/// Makes multichannel test signals from [ChannelRecipe]s, sample by
/// sample, the same for the same [seed] however it is divided into chunks.
///
/// Pure Dart; pace it with a [SynthRun] to send it in real time.
class SignalGenerator {
  final double rate;
  final List<ChannelRecipe> channels;
  final int seed;

  /// Index of the next sample.
  int sampleIndex = 0;

  late final List<List<SynthVoice>> _voices;
  final List<SynthEvent> _events = [];
  Float64List _scratch = Float64List(0);

  SignalGenerator({required this.rate, required this.channels, this.seed = 0})
    : assert(rate > 0) {
    _voices = [
      for (var c = 0; c < channels.length; c++)
        [
          for (var k = 0; k < channels[c].components.length; k++)
            channels[c].components[k].voice(
              rate,
              math.Random(_seedFor(channels[c].components[k].shared, c, k)),
            ),
        ],
    ];
  }

  /// The seed of a component's random sequence: the same on every
  /// platform (web included) and run, and the same on every channel for a
  /// [SynthComponent.shared] one.
  int _seedFor(String? shared, int channel, int component) {
    var h = _mix(0x811c9dc5, seed & 0xffffffff);
    h = _mix(h, (seed ~/ 0x100000000) & 0xffffffff);
    if (shared == null) {
      h = _mix(_mix(_mix(h, 1), channel), component);
    } else {
      h = _mix(h, 2);
      for (final u in shared.codeUnits) {
        h = _mix(h, u);
      }
    }
    return h & 0x7fffffff;
  }

  /// One step of FNV-1a, in 32 bits without exceeding 2^53 (for the web).
  static int _mix(int h, int v) {
    h = (h ^ v) & 0xffffffff;
    return ((h << 24) + (h << 8) + h * 0x93) & 0xffffffff;
  }

  int get channelCount => channels.length;

  List<String> get labels => [for (final c in channels) c.label];
  List<String> get units => [for (final c in channels) c.unit];

  /// Time of the next sample, in seconds from the start.
  double get time => sampleIndex / rate;

  /// Write the next [n] samples into [out], interleaved by channel
  /// (`out[i * channelCount + c]`), and return the events that began in
  /// them, each once even when on several channels.
  List<SynthEvent> fill(Float64List out, int n) {
    final ch = channelCount;
    assert(out.length >= n * ch);
    out.fillRange(0, n * ch, 0);
    _events.clear();
    final seen = <SynthEvent>{};
    void sink(int sample, String label) {
      final e = SynthEvent(sample, label);
      if (seen.add(e)) _events.add(e);
    }

    for (var c = 0; c < ch; c++) {
      for (final v in _voices[c]) {
        v.add(out, c, ch, sampleIndex, n, sink);
      }
      final clip = channels[c].clip;
      if (clip != null) {
        for (var i = 0; i < n; i++) {
          final j = i * ch + c;
          out[j] = out[j].clamp(-clip, clip);
        }
      }
    }
    sampleIndex += n;
    _events.sort((a, b) => a.sample.compareTo(b.sample));
    return List.unmodifiable(_events);
  }

  /// The next [n] samples, interleaved by channel, and their events.
  (Float64List, List<SynthEvent>) next(int n) {
    final out = Float64List(n * channelCount);
    return (out, fill(out, n));
  }

  /// Make and drop the next [n] samples (samples lost), keeping the signal
  /// continuous in time; returns their events.
  List<SynthEvent> skip(int n) {
    final need = n * channelCount;
    if (_scratch.length < need) _scratch = Float64List(need);
    return fill(_scratch, n);
  }
}
