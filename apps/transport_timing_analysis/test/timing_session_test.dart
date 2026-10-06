import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:timing_core/timing_core.dart';
import 'package:transport_timing_analysis/src/timing_session.dart';

RunLog log({required double sampleRate}) {
  final buffer = StringBuffer();
  final writer = RunLogWriter(
    buffer,
    RunHeader(
      runId: 'run1',
      startedAt: DateTime.utc(2026, 10, 6),
      deviceId: 'A',
      deviceName: 'a',
      sourceId: 'A',
      test: sampleRate > 0 ? 'latency' : 'interactive',
      backend: 'memory',
      sampleRate: sampleRate,
    ),
  );
  // 2 ms of latency; sample 3 is lost and sample 5 arrives twice.
  for (final seq in [1, 2, 4, 5, 5, 6]) {
    writer.received(
      'B',
      seq,
      sourceClock: seq * 0.01,
      receivedClock: 100 + seq * 0.01 + 0.002,
      clockOffset: 100,
      uncertainty: 0.0004,
    );
  }
  return RunLog.parse(const LineSplitter().convert(buffer.toString()));
}

void main() {
  test('a latency run is laid out by sequence number', () async {
    final session = TimingSession(
      'a.ttlog',
      log(sampleRate: 100),
      nameOf: (id) => id == 'B' ? 'b' : null,
    );
    final info = session.streams.single;
    expect(info.name, 'b → a');
    expect(info.rate, 100);
    expect(info.labels.first, 'latency');

    final source = session.sourceFor(info);
    expect(source.end, closeTo(0.06, 1e-9));
    final window = (await source.read(0, 1, DerivedSpec.none))!;
    final latency = window.channels[0];
    expect(latency, hasLength(6));
    expect(latency[0], closeTo(2, 1e-3));
    expect(latency[2], isNaN, reason: 'the lost sample is a gap');
    expect(latency[5], closeTo(2, 1e-3));
    expect(
      window.channels[3][0],
      closeTo(0.2, 1e-6),
      reason: 'half the round trip',
    );

    final envelope = (await source.envelope(0, 0.06, 2, DerivedSpec.none))!;
    expect(envelope.stats[0].count, 5);
    expect(source.events().length, 0);
  });

  test('an interactive run is laid out by arrival', () {
    final session = TimingSession(
      'a.ttlog',
      log(sampleRate: 0),
      nameOf: (_) => null,
    );
    final info = session.streams.single;
    expect(info.name, 'B → a');
    expect(info.irregular, isTrue);
    final events = session.sourceFor(info).events();
    expect(events.length, 6);
    expect(events.times.first, 0);
    expect(events.channels[0][0], closeTo(2, 1e-3));
  });
}
