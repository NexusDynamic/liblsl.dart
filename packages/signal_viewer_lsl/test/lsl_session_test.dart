import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer_lsl/signal_viewer_lsl.dart';

/// An [LslSession] on a stream that is really being sent, received both
/// ways.
void main() {
  Future<LslStreamDescription> find(LslDiscovery d, String name) async {
    for (var i = 0; i < 100; i++) {
      final s = (await d.streams()).where((s) => s.name == name);
      if (s.isNotEmpty) return s.first;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('$name not found');
  }

  for (final eventDriven in [true, false]) {
    test('receives ${eventDriven ? 'as samples arrive' : 'on a timer'}, '
        'and closes', () async {
      final name =
          'session_${eventDriven}_${DateTime.now().microsecondsSinceEpoch}';
      final generator = await LslSignalGenerator.start(
        name: name,
        channels: 4,
        rate: 500,
      );
      final discovery = lsl.discover();
      final session = await LslSession.open(
        await find(discovery, name),
        LslInletOptions(eventDriven: eventDriven),
      );
      for (var i = 0; i < 250 && session.received < 500; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(session.received, greaterThanOrEqualTo(500));
      expect(session.error, isNull);
      expect(session.receiving!.eventDriven, eventDriven);
      expect(session.receiveNote, isNull);
      expect(session.titleSuffix, isEmpty);
      expect(session.lostSampleCount, 0);
      expect(session.measuredRate, closeTo(500, 25));

      await session.close();
      expect(session.closed, isTrue);
      final after = session.received;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(session.received, after);
      await generator.close();
      discovery.close();
    });
  }
}
