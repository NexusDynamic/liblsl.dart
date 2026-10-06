import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:timing_core/timing_core.dart';

RunHeader header(
  String device, {
  String runId = 'run1',
  String? sourceId,
  double? pollInterval,
}) => RunHeader(
  runId: runId,
  startedAt: DateTime.utc(2026, 10, 6),
  deviceId: device,
  deviceName: device,
  sourceId: sourceId,
  test: 'latency',
  backend: 'memory',
  sampleRate: 100,
  receiveMode: pollInterval == null ? 'event' : 'polled',
  pollInterval: pollInterval,
);

RunLog parse(StringBuffer buffer) =>
    RunLog.parse(const LineSplitter().convert(buffer.toString()));

void main() {
  group('Summary', () {
    test('known values', () {
      final s = Summary.of([for (var i = 1; i <= 101; i++) i.toDouble()])!;
      expect(s.count, 101);
      expect(s.mean, 51);
      expect(s.min, 1);
      expect(s.max, 101);
      expect(s.p50, 51);
      expect(s.p95, closeTo(96, 1e-9));
      expect(s.sd, closeTo(sqrt(101 * 102 / 12), 1e-9));
    });

    test('skips NaN and is null when nothing is left', () {
      expect(Summary.of([double.nan, 2, 4])!.mean, 3);
      expect(Summary.of([double.nan]), isNull);
      expect(Summary.of([]), isNull);
    });
  });

  test('LinearFit recovers a line on large x', () {
    final x = [for (var i = 0; i < 50; i++) 700000.0 + i * 5];
    final y = [for (final v in x) 0.25 + 20e-6 * (v - 700000)];
    final fit = LinearFit.of(x, y)!;
    expect(fit.slope, closeTo(20e-6, 1e-12));
    expect(fit.at(700100), closeTo(0.252, 1e-9));
    expect(fit.residualSd, lessThan(1e-9));
  });

  group('run log', () {
    test('round trip keeps values and nulls', () {
      final buffer = StringBuffer();
      RunLogWriter(buffer, header('a', sourceId: 'src,a'))
        ..sent(1, 10.5)
        ..received('src,b', 7, receivedClock: 11.25, sourceClock: 3.5)
        ..received(
          'src,b',
          8,
          receivedClock: 11.5,
          sourceClock: 3.75,
          clockOffset: 7.5,
          uncertainty: 0.001,
        )
        ..clockSync('src,b', receivedClock: 11, offset: 7.5, clockReset: true)
        ..marker('touch', 1, 10.4)
        ..marker('shown', 7, 11.3, sourceId: 'src,b')
        ..event(10, 'started', {'note': 'a,b'});

      final log = parse(buffer);
      expect(log.header.sourceId, 'src,a');
      expect(log.header.receiveMode, 'event');
      expect(log.sent.seq, [1]);
      expect(log.sent.sendClock, [10.5]);
      final r = log.received['src,b']!;
      expect(r.seq, [7, 8]);
      expect(r.clockOffset[0], isNaN);
      expect(r.clockOffset[1], 7.5);
      expect(r.uncertainty[1], 0.001);
      final c = log.syncs['src,b']!;
      expect(c.offset, [7.5]);
      expect(c.remoteTime[0], isNaN);
      expect(c.clockReset, [true]);
      expect(log.markers.map((m) => (m.kind, m.id, m.sourceId)), [
        ('touch', 1, null),
        ('shown', 7, 'src,b'),
      ]);
      expect(log.events.single.detail, {'note': 'a,b'});
    });

    test('rejects other files and malformed rows', () {
      expect(
        () => RunLog.parse(['log_timestamp\ttimestamp']),
        throwsFormatException,
      );
      expect(() => RunLog.parse(['{"format":"other"}']), throwsFormatException);
      expect(() => RunLog.parse([]), throwsFormatException);
      final head = jsonEncode(header('a').toJson());
      expect(() => RunLog.parse([head, 'S,1']), throwsFormatException);
      expect(() => RunLog.parse([head, 'X,1']), throwsFormatException);
      expect(() => RunLog.parse([head, 'R,0,1,,1,,']), throwsFormatException);
    });
  });

  group('analyse', () {
    // Sender b's clock runs 1000 s behind a's and drifts by 50 ppm; samples
    // take exactly 2 ms. Sequence 10 is lost, 20 arrives twice, and 30 and
    // 31 swap.
    const latency = 0.002;
    const drift = 50e-6;
    double offsetAt(double bClock) => 1000 + drift * bClock;

    late Report report;
    late PairReport pair;

    setUp(() {
      final a = StringBuffer();
      final b = StringBuffer();
      final receiver = RunLogWriter(a, header('a', sourceId: 'A'));
      final sender = RunLogWriter(b, header('b', sourceId: 'B'));

      for (var k = 0; k <= 10; k++) {
        final bClock = k * 0.1;
        receiver.clockSync(
          'B',
          receivedClock: bClock + offsetAt(bClock),
          offset: offsetAt(bClock),
          remoteTime: bClock,
          uncertainty: 0.0004,
        );
      }

      final order = [for (var seq = 1; seq <= 100; seq++) seq]
        ..remove(10)
        ..insert(19, 20)
        ..[29] = 31
        ..[30] = 30;
      for (var seq = 1; seq <= 100; seq++) {
        sender.sent(seq, seq * 0.01);
      }
      for (final seq in order) {
        final sendClock = seq * 0.01;
        receiver.received(
          'B',
          seq,
          sourceClock: sendClock,
          receivedClock: sendClock + offsetAt(sendClock) + latency,
          clockOffset: offsetAt(sendClock),
          uncertainty: 0.0004,
        );
      }

      report = analyse([parse(a), parse(b)]);
      pair = report.runs.single.pairs.single;
    });

    test('names the pair from the sender log', () {
      expect(pair.from, 'b');
      expect(pair.to, 'a');
      expect(pair.loopback, isFalse);
    });

    test('latency with recorded and fitted offsets', () {
      expect(pair.latency!.mean, closeTo(latency, 1e-9));
      expect(pair.latency!.sd, lessThan(1e-9));
      expect(pair.latencyFitted!.mean, closeTo(latency, 1e-9));
      expect(pair.latencyRaw!.mean, closeTo(1000, 1));
      expect(pair.untimed, 0);
      expect(pair.uncertainty!.p50, 0.0004);
    });

    test('loss, duplicates and reordering', () {
      expect(pair.sent, 100);
      expect(pair.received, 100);
      expect(pair.lost, 1);
      expect(pair.duplicates, 1);
      expect(pair.reordered, 1);
      expect(pair.lossRate, closeTo(0.01, 1e-12));
    });

    test('intervals', () {
      expect(pair.sendInterval!.mean, closeTo(0.01, 1e-9));
      expect(pair.sendInterval!.sd, lessThan(1e-9));
      final sender = report.runs.single.senders.single;
      expect(sender.device, 'b');
      expect(sender.sent, 100);
      expect(sender.achievedRate, closeTo(100, 1e-6));
    });

    test('clock drift', () {
      final clock = pair.clock!;
      expect(clock.estimates, 11);
      expect(clock.resets, 0);
      expect(clock.driftPpm, closeTo(50, 1e-3));
      expect(clock.offsetFirst, closeTo(1000, 1e-9));
    });

    test('report serialises', () {
      final json = jsonDecode(jsonEncode(report.toJson())) as Map;
      expect((json['runs'] as List).single['pairs'], hasLength(1));
      expect(formatReport(report), contains('b -> a'));
    });
  });

  test('without the sender log, loss comes from sequence gaps', () {
    final a = StringBuffer();
    final w = RunLogWriter(a, header('a', pollInterval: 0.001));
    for (final seq in [5, 6, 8, 9]) {
      w.received('B', seq, receivedClock: seq * 1.0, sourceClock: seq * 1.0);
    }
    final pair = analyse([parse(a)]).runs.single.pairs.single;
    expect(pair.from, 'B');
    expect(pair.sent, isNull);
    expect(pair.lost, 1);
    expect(pair.untimed, 4);
    expect(pair.latency, isNull);
    expect(pair.latencyRaw!.mean, 0);
    expect(pair.clock, isNull);
    expect(pair.pollInterval, 0.001);
    expect(
      formatReport(analyse([parse(a)])),
      contains('polled every 1.000 ms'),
    );
  });

  test('a clock reset restarts the fit', () {
    final a = StringBuffer();
    final w = RunLogWriter(a, header('a'));
    for (var k = 0; k < 5; k++) {
      w.clockSync(
        'B',
        receivedClock: 100.0 + k,
        offset: 100,
        remoteTime: k * 1.0,
      );
    }
    for (var k = 0; k < 8; k++) {
      w.clockSync(
        'B',
        receivedClock: 105.0 + k,
        offset: 5,
        remoteTime: 100.0 + k,
        clockReset: k == 0,
      );
    }
    w
      ..received('B', 1, receivedClock: 102.5, sourceClock: 2, clockOffset: 100)
      ..received(
        'B',
        2,
        receivedClock: 108.5,
        sourceClock: 103,
        clockOffset: 5,
      );
    final pair = analyse([parse(a)]).runs.single.pairs.single;
    expect(pair.clock!.resets, 1);
    expect(pair.clock!.estimates, 13);
    expect(pair.clock!.driftPpm, closeTo(0, 1e-6));
    expect(pair.clock!.offsetLast, 5);
    expect(pair.series.latencyFitted, [closeTo(0.5, 1e-9), closeTo(0.5, 1e-9)]);
  });

  test('loopback and interactive delays', () {
    final a = StringBuffer();
    RunLogWriter(a, header('a', sourceId: 'A'))
      ..marker('touch', 1, 9.99)
      ..sent(1, 10)
      ..received('A', 1, receivedClock: 10.001, sourceClock: 10, clockOffset: 0)
      ..marker('shown', 1, 10.017);
    final run = analyse([parse(a)]).runs.single;
    expect(run.pairs.single.loopback, isTrue);
    final interactive = run.interactive.single;
    expect(interactive.touchToSend!.mean, closeTo(0.01, 1e-9));
    expect(interactive.receiveToShown['a']!.mean, closeTo(0.016, 1e-9));
  });

  test('runs are kept apart', () {
    final one = StringBuffer();
    final two = StringBuffer();
    RunLogWriter(one, header('a', runId: 'r1')).sent(1, 0);
    RunLogWriter(two, header('a', runId: 'r2')).sent(1, 0);
    expect(analyse([parse(one), parse(two)]).runs.map((r) => r.runId), [
      'r1',
      'r2',
    ]);
  });
}
