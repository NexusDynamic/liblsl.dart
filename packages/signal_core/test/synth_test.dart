import 'dart:math' as math;
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';
import 'package:test/test.dart';

/// Channel [c] of interleaved [values] with [channels] channels.
List<double> _channel(Float64List values, int channels, int c) => [
  for (var i = c; i < values.length; i += channels) values[i],
];

/// Power of [x] at [f] Hz (Goertzel), normalised by length.
double _power(List<double> x, double f, double rate) {
  final w = 2 * math.pi * f / rate;
  final k = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (final v in x) {
    final s = v + k * s1 - s2;
    s2 = s1;
    s1 = s;
  }
  final p = s1 * s1 + s2 * s2 - k * s1 * s2;
  return p / (x.length * x.length);
}

double _std(List<double> x) {
  final m = x.reduce((a, b) => a + b) / x.length;
  var v = 0.0;
  for (final e in x) {
    v += (e - m) * (e - m);
  }
  return math.sqrt(v / x.length);
}

void main() {
  group('SignalGenerator', () {
    for (final preset in SynthPreset.values) {
      test('${preset.name}: the same however it is chunked', () {
        final spec = SynthSpec(preset: preset, channels: 6, seed: 3);
        final (whole, wholeEvents) = spec.generator().next(1000);
        final g = spec.generator();
        final parts = <double>[];
        final events = <SynthEvent>[];
        for (final n in [1, 99, 250, 7, 143, 500]) {
          final (v, e) = g.next(n);
          parts.addAll(v);
          events.addAll(e);
        }
        expect(parts, whole);
        expect(events, wholeEvents);
      });
    }

    test('the same for the same seed, different for another', () {
      const spec = SynthSpec(preset: SynthPreset.eegArtefacts, seed: 7);
      final a = spec.generator().next(500).$1;
      final b = spec.generator().next(500).$1;
      final c = spec.copyWith(seed: 8).generator().next(500).$1;
      expect(a, b);
      expect(a, isNot(c));
    });

    test('skip keeps the signal continuous', () {
      const spec = SynthSpec(preset: SynthPreset.eegResting, channels: 2);
      final whole = spec.generator().next(300).$1;
      final g = spec.generator()..skip(100);
      expect(g.next(200).$1, whole.sublist(200));
    });

    test('sines are at their frequency and below Nyquist', () {
      const spec = SynthSpec(channels: 30, rate: 250, noise: 0);
      final g = spec.generator();
      final (v, _) = g.next(2500);
      for (var c = 0; c < 30; c++) {
        final f = 10.0 * (c % 11 + 1); // multiples of 10 below 112.5 Hz
        final x = _channel(v, 30, c);
        expect(_power(x, f, 250), closeTo(0.25 * 50 * 50, 1), reason: 'ch$c');
        expect(_power(x, f + 3, 250), lessThan(1));
      }
    });

    test('line noise and its harmonics', () {
      const spec = SynthSpec(
        preset: SynthPreset.lineNoise,
        channels: 1,
        rate: 1000,
        lineFrequency: 60,
      );
      final x = _channel(spec.generator().next(4000).$1, 1, 0);
      expect(_power(x, 60, 1000), closeTo(0.25 * 50 * 50, 5));
      expect(_power(x, 120, 1000), closeTo(0.25 * 25 * 25, 5));
      expect(_power(x, 50, 1000), lessThan(1));
    });

    test('white and pink noise have the given size; pink falls as 1/f', () {
      const rate = 1000.0;
      final g = SignalGenerator(
        rate: rate,
        channels: const [
          ChannelRecipe('white', [WhiteNoise(10)]),
          ChannelRecipe('pink', [PinkNoise(10)]),
        ],
        seed: 1,
      );
      final (v, _) = g.next(200000);
      expect(_std(_channel(v, 2, 0)), closeTo(10, 0.2));
      final pink = _channel(v, 2, 1);
      expect(_std(pink), closeTo(10, 1.5));

      // Average power in bands an octave apart: about half per octave.
      double band(double f) {
        var p = 0.0;
        for (var k = 0; k < 20; k++) {
          p += _power(pink, f * (1 + k / 40), rate);
        }
        return p;
      }

      final slope = math.log(band(80) / band(10)) / math.log(8);
      expect(slope, closeTo(-1, 0.3));
    });

    test('clip holds values at the limit; flat is flat', () {
      final g = SignalGenerator(
        rate: 100,
        channels: [
          const ChannelRecipe('clipped', [Sine(1, 10)], clip: 5),
          ChannelRecipe.flat('flat'),
        ],
      );
      final (v, _) = g.next(100);
      final clipped = _channel(v, 2, 0);
      expect(clipped.reduce(math.max), 5);
      expect(clipped.reduce(math.min), -5);
      expect(_channel(v, 2, 1).every((e) => e == 0), isTrue);
    });

    test('shared events are reported once, at the same sample on each '
        'channel', () {
      final g = SignalGenerator(
        rate: 250,
        channels: const [
          ChannelRecipe('a', [Blinks(100, perMinute: 120)]),
          ChannelRecipe('b', [Blinks(50, perMinute: 120)]),
        ],
        seed: 2,
      );
      final (v, events) = g.next(250 * 30);
      final blinks = events.where((e) => e.label == 'blink').toList();
      expect(blinks.length, inInclusiveRange(20, 120));
      expect(blinks.toSet().length, blinks.length);
      final a = _channel(v, 2, 0), b = _channel(v, 2, 1);
      for (var i = 0; i < a.length; i++) {
        expect(a[i], closeTo(2 * b[i], 1e-9));
      }
      // The signal starts rising at each blink.
      for (final e in blinks) {
        expect(a[e.sample], 0);
        if (e.sample + 10 < a.length) expect(a[e.sample + 10], greaterThan(0));
      }
    });

    test('impulses at their interval', () {
      final g = SignalGenerator(
        rate: 100,
        channels: const [
          ChannelRecipe('i', [ImpulseTrain(0.5, 1)]),
        ],
      );
      final (v, events) = g.next(200);
      expect([for (final e in events) e.sample], [0, 50, 100, 150]);
      expect(v.where((e) => e != 0).length, 4);
    });

    test('phase stays exact far from the start', () {
      final g = SignalGenerator(
        rate: 1000,
        channels: const [
          ChannelRecipe('s', [Sine(10, 1)]),
        ],
      );
      g.sampleIndex = 1000 * 3600 * 24 * 30; // 30 days in
      final (v, _) = g.next(100);
      expect(v[0], closeTo(0, 1e-9));
      expect(v[25], closeTo(1, 1e-9));
    });
  });

  group('SynthRun', () {
    test('sends samples as they fall due, stamped on the clock', () {
      var now = 100.0;
      final chunks = <SynthChunk>[];
      final run = SynthRun(
        const SynthSpec(channels: 2, rate: 100).generator(),
        clock: () => now,
        onChunk: chunks.add,
        tick: null,
      );
      now += 0.105;
      run.pump();
      now += 0.2;
      run.pump();
      expect([for (final c in chunks) c.count], [10, 20]);
      expect(chunks[1].first, 10);
      expect(chunks[1].times.first, closeTo(100.1, 1e-9));
      expect(chunks[1].values.length, 40);
      expect(run.sent, 30);
    });

    test('dropouts lose samples; the signal carries on after them', () {
      var now = 0.0;
      final chunks = <SynthChunk>[];
      const spec = SynthSpec(channels: 1, rate: 100, noise: 0);
      final run = SynthRun(
        spec.generator(),
        clock: () => now,
        onChunk: chunks.add,
        impairments: const Impairments(dropoutRate: 2, dropoutS: 0.1),
        tick: null,
      );
      for (var i = 1; i <= 1000; i++) {
        now = i / 50;
        run.pump();
      }
      expect(run.lost, greaterThan(0));
      expect(run.sent + run.lost, 2000);
      final reference = spec.generator().next(2000).$1;
      for (final c in chunks) {
        for (var i = 0; i < c.count; i++) {
          expect(c.values[i], reference[c.first + i]);
          expect(c.times[i], closeTo((c.first + i) / 100, 1e-9));
        }
      }
    });

    test('a long pause is dropped beyond maxCatchUpS', () {
      var now = 0.0;
      final run = SynthRun(
        const SynthSpec(channels: 1, rate: 100).generator(),
        clock: () => now,
        onChunk: (_) {},
        tick: null,
      );
      now = 10;
      run.pump();
      expect(run.sent, 100);
      expect(run.lost, 900);
    });

    test('jitter moves time stamps', () {
      var now = 0.0;
      final chunks = <SynthChunk>[];
      final run = SynthRun(
        const SynthSpec(channels: 1, rate: 1000).generator(),
        clock: () => now,
        onChunk: chunks.add,
        impairments: const Impairments(jitterS: 0.001),
        tick: null,
      );
      now = 1;
      run.pump();
      final errors = [
        for (var i = 0; i < 1000; i++) chunks.single.times[i] - i / 1000,
      ];
      expect(_std(errors), closeTo(0.001, 0.0002));
    });

    test('markers every second and at events', () {
      var now = 0.0;
      final markers = <SynthMarker>[];
      final run = SynthRun(
        SignalGenerator(
          rate: 100,
          channels: const [
            ChannelRecipe('i', [ImpulseTrain(0.5, 1)]),
          ],
        ),
        clock: () => now,
        onChunk: (_) {},
        markers: const MarkerSchedule(every: 1),
        onMarkers: markers.addAll,
        tick: null,
      );
      for (var i = 1; i <= 25; i++) {
        now = i / 10;
        run.pump();
      }
      expect(
        [for (final m in markers) m.text],
        [
          'impulse',
          'impulse',
          'impulse',
          'tick 1',
          'impulse',
          'impulse',
          'tick 2',
        ],
      );
      expect(markers[3].time, closeTo(1, 1e-9));
    });
  });
}
