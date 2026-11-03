import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';

void main() {
  group('SyntheticSession', () {
    test('samples on the grid of its rate as they fall due', () async {
      var now = 0.0;
      final s = SyntheticSession(
        'test',
        const SynthOptions(spec: SynthSpec(channels: 3, rate: 100)),
        clock: () => now,
        tick: null,
      );
      addTearDown(s.close);
      expect(s.streams, hasLength(1));
      final refs = s.info.channels;
      expect(s.tickRange(refs, 100), isNull);
      now = 0.5;
      s.pump();
      expect(s.tickRange(refs, 100), (0, 50));
      expect(s.now, closeTo(0.5, 1e-9));
      final cols = s.columnsAt(refs, 100, 0, 50)!;
      final reference = const SynthSpec(
        channels: 3,
        rate: 100,
      ).generator().next(50).$1;
      for (var i = 0; i < 50; i++) {
        expect(cols[1][i], reference[i * 3 + 1]);
      }
      final window = await s.sourceFor(s.info).read(0, 0.5, DerivedSpec.none);
      expect(window!.channels.first.length, 50);
    });

    test('dropouts are filled; markers are a stream of their own', () {
      var now = 0.0;
      final s = SyntheticSession(
        'test',
        const SynthOptions(
          spec: SynthSpec(preset: SynthPreset.eegArtefacts, rate: 200),
          markers: MarkerSchedule(every: 0.5),
          impairments: Impairments(dropoutRate: 1, dropoutS: 0.1),
        ),
        clock: () => now,
        tick: null,
      );
      addTearDown(s.close);
      for (var i = 1; i <= 500; i++) {
        now = i / 50;
        s.pump();
      }
      expect(s.lost, greaterThan(0));
      // Every sample is in the ring, lost ones filled in.
      expect(s.tickRange(s.info.channels, 200), (0, 2000));
      final markers = s.markerInfo!;
      expect(markers.irregular, isTrue);
      expect(s.streams, [s.info, markers]);
      final e = s.sourceFor(markers).events();
      final ticks = [
        for (var i = 0; i < e.length; i++)
          if (e.text![0][i].startsWith('tick')) e.times[i],
      ];
      expect(ticks.length, 19);
      expect(ticks.first, closeTo(0.5, 1e-9));
      expect(e.markers, isTrue);
    });
  });
}
