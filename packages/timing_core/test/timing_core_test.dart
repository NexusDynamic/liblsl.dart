import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:timing_core/timing_core.dart';
import 'package:xdf/xdf.dart';

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

/// The bytes of a log with [header], filled by [fill].
Future<Uint8List> record(
  RunHeader header,
  void Function(RunLogWriter log) fill,
) async {
  final sink = BytesSink();
  final log = RunLogWriter(sink, header);
  fill(log);
  await log.close();
  return sink.takeBytes();
}

Future<RunLog> recorded(
  RunHeader header,
  void Function(RunLogWriter log) fill,
) async => RunLog.parse(await record(header, fill));

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
    void fill(RunLogWriter log) => log
      ..clockSync('src,b', receivedClock: 11, offset: 7.5, clockReset: true)
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
      ..received('other', 1, receivedClock: 12)
      ..marker('touch', 1, 10.4)
      ..marker('shown', 7, 11.3, sourceId: 'src,b with spaces')
      ..event(10, 'started', {'note': 'a,b'})
      ..event(13, 'stopped');

    test('round trip keeps values and nulls', () async {
      final log = await recorded(header('a', sourceId: 'src,a'), fill);
      expect(log.header.sourceId, 'src,a');
      expect(log.header.receiveMode, 'event');
      expect(log.sent.seq, [1]);
      expect(log.sent.sendClock, [10.5]);
      final r = log.received['src,b']!;
      expect(r.seq, [7, 8]);
      expect(r.sourceClock, [3.5, 3.75]);
      expect(r.receivedClock, [11.25, 11.5]);
      expect(r.clockOffset[0], isNaN);
      expect(r.clockOffset[1], 7.5);
      expect(r.uncertainty[1], 0.001);
      expect(log.received['other']!.sourceClock[0], isNaN);
      final c = log.syncs['src,b']!;
      expect(c.offset, [7.5]);
      expect(c.receivedClock, [11]);
      expect(c.remoteTime[0], isNaN);
      expect(c.clockReset, [true]);
      expect(log.markers.map((m) => (m.kind, m.id, m.clock, m.sourceId)), [
        ('touch', 1, 10.4, null),
        ('shown', 7, 11.3, 'src,b with spaces'),
      ]);
      expect(log.events.map((e) => e.name), ['started', 'stopped']);
      expect(log.events.first.detail, {'note': 'a,b'});
      expect(log.events.last.detail, isNull);
    });

    test('many samples survive the chunking', () async {
      final log = await recorded(header('a'), (log) {
        for (var seq = 1; seq <= 2000; seq++) {
          log.received(
            'B',
            seq,
            receivedClock: seq + 0.5,
            sourceClock: seq * 1.0,
          );
        }
      });
      final r = log.received['B']!;
      expect(r.seq, [for (var seq = 1; seq <= 2000; seq++) seq]);
      expect(r.receivedClock.last, 2000.5);
    });

    test('is an XDF file any reader can open and synchronise', () async {
      final recording = loadXdf(await record(header('a', sourceId: 'A'), fill));
      expect(recording.streams.map((s) => s.info.name), [
        'tt.clock',
        'tt.sent',
        'tt.received',
        'tt.received',
        'tt.markers',
        'tt.events',
      ]);
      final received = recording.streams.firstWhere(
        (s) => s.info.name == 'tt.received' && s.info.sourceId == 'src,b',
      );
      expect(received.info.channels.map((c) => c.label), [
        'seq',
        'source_clock',
        'received_clock',
        'clock_offset',
        'uncertainty',
      ]);
      // The estimate made before the stream existed is still its clock
      // offset, so the reader has mapped the sender's 3.5 onto this
      // device's clock.
      expect(received.clockValues, [7.5]);
      expect(received.timestamps[0], closeTo(11, 1e-9));
      expect(recording.stream('tt.markers')!.strings.first, ['touch 1']);
    });

    test('a reader that synchronises gets the receiving clock, however far '
        'apart and drifting the two clocks are', () async {
      // Clocks a day of uptime apart, drifting by 50 ppm.
      double offsetAt(double source) => 1e5 + 50e-6 * (source - 1000);
      final bytes = await record(header('a'), (log) {
        for (var k = 0; k <= 60; k += 5) {
          final remote = 1000.0 + k;
          log.clockSync(
            'B',
            receivedClock: remote + offsetAt(remote),
            offset: offsetAt(remote),
            remoteTime: remote,
          );
        }
        for (var seq = 0; seq < 600; seq++) {
          final sent = 1000 + seq / 10;
          log.received(
            'B',
            seq,
            receivedClock: sent + offsetAt(sent) + 0.002,
            sourceClock: sent,
            clockOffset: offsetAt(sent),
          );
        }
      });
      final received = loadXdf(
        bytes,
      ).streams.firstWhere((s) => s.info.name == 'tt.received');
      for (final i in [0, 299, 599]) {
        final sent = 1000 + i / 10;
        expect(received.timestamps[i], closeTo(sent + offsetAt(sent), 1e-6));
        // received_clock − time stamp: the README's one subtraction.
        expect(
          received.channels[2][i] - received.timestamps[i],
          closeTo(0.002, 1e-6),
        );
      }
    });

    test('rejects files that are not run logs', () async {
      expect(() => RunLog.parse(Uint8List(0)), throwsFormatException);
      expect(
        () => RunLog.parse(utf8.encode('log_timestamp\ttimestamp\n')),
        throwsFormatException,
      );
      final sink = BytesSink();
      final other = XdfWriter(sink)
        ..addStream(1, XdfStreamInfo(name: 'EEG', channelCount: 1))
        ..writeSamples(1, [1], [2]);
      await other.close();
      expect(() => RunLog.parse(sink.takeBytes()), throwsFormatException);
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

    setUp(() async {
      final a = BytesSink();
      final b = BytesSink();
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

      await receiver.close();
      await sender.close();
      report = analyse([
        RunLog.parse(a.takeBytes()),
        RunLog.parse(b.takeBytes()),
      ]);
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

  test('without the sender log, loss comes from sequence gaps', () async {
    final log = await recorded(header('a', pollInterval: 0.001), (w) {
      for (final seq in [5, 6, 8, 9]) {
        w.received('B', seq, receivedClock: seq * 1.0, sourceClock: seq * 1.0);
      }
    });
    final report = analyse([log]);
    final pair = report.runs.single.pairs.single;
    expect(pair.from, 'B');
    expect(pair.sent, isNull);
    expect(pair.lost, 1);
    expect(pair.untimed, 4);
    expect(pair.latency, isNull);
    expect(pair.latencyRaw!.mean, 0);
    expect(pair.clock, isNull);
    expect(pair.pollInterval, 0.001);
    expect(formatReport(report), contains('polled every 1.000 ms'));
  });

  test('a clock reset restarts the fit', () async {
    final log = await recorded(header('a'), (w) {
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
        ..received(
          'B',
          1,
          receivedClock: 102.5,
          sourceClock: 2,
          clockOffset: 100,
        )
        ..received(
          'B',
          2,
          receivedClock: 108.5,
          sourceClock: 103,
          clockOffset: 5,
        );
    });
    final pair = analyse([log]).runs.single.pairs.single;
    expect(pair.clock!.resets, 1);
    expect(pair.clock!.estimates, 13);
    expect(pair.clock!.driftPpm, closeTo(0, 1e-6));
    expect(pair.clock!.offsetLast, 5);
    expect(pair.series.latencyFitted, [closeTo(0.5, 1e-9), closeTo(0.5, 1e-9)]);
  });

  test('a clock reset that sets the sender back restarts the fit', () async {
    // A restarted device: its clock read about 1000 and starts again at 0.
    final log = await recorded(header('a'), (w) {
      for (var k = 0; k < 5; k++) {
        w.clockSync(
          'B',
          receivedClock: 100.0 + k,
          offset: -900,
          remoteTime: 1000.0 + k,
        );
      }
      for (var k = 0; k < 8; k++) {
        w.clockSync(
          'B',
          receivedClock: 105.0 + k,
          offset: 105,
          remoteTime: k * 1.0,
          clockReset: k == 0,
        );
      }
      w
        ..received(
          'B',
          1,
          receivedClock: 102.5,
          sourceClock: 1002,
          clockOffset: -900,
        )
        ..received(
          'B',
          2,
          receivedClock: 108.5,
          sourceClock: 3,
          clockOffset: 105,
        );
    });
    final pair = analyse([log]).runs.single.pairs.single;
    expect(pair.clock!.resets, 1);
    expect(pair.series.latencyFitted, [closeTo(0.5, 1e-9), closeTo(0.5, 1e-9)]);
  });

  test('without clock-sync samples, the offsets on the samples are the '
      'estimates', () async {
    // As WebSocket and WebRTC report: an offset with each sample, stepping
    // once a second as a new estimate lands. The sender's clock drifts by
    // 100 ppm and samples take 1 ms.
    const drift = 100e-6;
    final log = await recorded(header('a'), (w) {
      for (var seq = 0; seq < 1000; seq++) {
        final sendClock = seq * 0.01;
        final trueOffset = 50 + drift * sendClock;
        w.received(
          'B',
          seq,
          sourceClock: sendClock,
          receivedClock: sendClock + trueOffset + 0.001,
          clockOffset: 50 + drift * sendClock.floorToDouble(),
          uncertainty: 0.002,
        );
      }
    });
    final pair = analyse([log]).runs.single.pairs.single;
    expect(pair.clock!.estimates, 10);
    expect(pair.clock!.driftPpm, closeTo(100, 0.01));
    // The stepped offset is up to a second of drift out; the fit is not.
    expect(pair.latency!.max - pair.latency!.min, closeTo(99e-6, 2e-6));
    expect(pair.latencyFitted!.mean, closeTo(0.001, 1e-7));
    expect(pair.latencyFitted!.sd, lessThan(1e-7));
  });

  test('loopback and interactive delays', () async {
    final log = await recorded(
      header('a', sourceId: 'A'),
      (w) => w
        ..marker('touch_os', 1, 9.982)
        ..marker('touch', 1, 9.99)
        ..sent(1, 10)
        ..received(
          'A',
          1,
          receivedClock: 10.001,
          sourceClock: 10,
          clockOffset: 0,
        )
        ..marker('shown', 1, 10.017),
    );
    final run = analyse([log]).runs.single;
    expect(run.pairs.single.loopback, isTrue);
    expect(run.pairs.single.latency!.mean, closeTo(0.001, 1e-9));
    final interactive = run.interactive.single;
    expect(interactive.touchToSend!.mean, closeTo(0.01, 1e-9));
    expect(interactive.reportedToHeard!.mean, closeTo(0.008, 1e-9));
    expect(
      formatReport(Report([run])),
      contains('touch stamped -> heard  n=1 mean 8.000'),
    );
    expect(interactive.receiveToShown['a']!.mean, closeTo(0.016, 1e-9));
  });

  test('a device needs no clock offset for its own samples', () async {
    final log = await recorded(
      header('a', sourceId: 'A'),
      (w) => w
        ..received('A', 1, receivedClock: 10.002, sourceClock: 10)
        ..received('B', 1, receivedClock: 10.002, sourceClock: 10),
    );
    final pairs = analyse([log]).runs.single.pairs;
    final own = pairs.firstWhere((p) => p.loopback);
    expect(own.untimed, 0);
    expect(own.latency!.mean, closeTo(0.002, 1e-9));
    expect(own.latencyFitted!.mean, closeTo(0.002, 1e-9));
    final other = pairs.firstWhere((p) => !p.loopback);
    expect(other.untimed, 1);
    expect(other.latency, isNull);
  });

  test('a summary sorts as the library does, whatever the values', () {
    final random = Random(7);
    final cases = <List<double>>[
      [for (var i = 0; i < 5000; i++) random.nextDouble()],
      [for (var i = 0; i < 5000; i++) i.toDouble()],
      [for (var i = 5000; i > 0; i--) i.toDouble()],
      // Few distinct values, as a clock bound has.
      [for (var i = 0; i < 5000; i++) random.nextInt(4) * 0.001],
      List.filled(5000, 2.5),
      [for (var i = 0; i < 17; i++) -i * 1.5],
      [3, 1],
      [1],
    ];
    for (final values in cases) {
      final sorted = [...values]..sort();
      double quantile(List<double> of, double q) {
        final position = q * (of.length - 1);
        final lower = position.floor(), upper = position.ceil();
        return of[lower] + (of[upper] - of[lower]) * (position - lower);
      }

      final s = Summary.of(values)!;
      expect(s.min, sorted.first);
      expect(s.max, sorted.last);
      for (final (q, value) in [
        (0.5, s.p50),
        (0.95, s.p95),
        (0.99, s.p99),
        (0.999, s.p999),
      ]) {
        expect(value, quantile(sorted, q), reason: '$q of ${values.length}');
      }
      final deviations = [for (final v in sorted) (v - s.p50).abs()]..sort();
      expect(s.mad, quantile(deviations, 0.5), reason: '${values.length}');
    }
  });

  test('robust spread and percentiles that need more values', () {
    final values = [for (var i = 1; i <= 99; i++) i.toDouble(), 10000.0];
    final s = Summary.of(values)!;
    expect(s.mad, closeTo(25, 1e-9));
    expect(s.iqr, closeTo(49.5, 1e-9));
    expect(s.sd, greaterThan(900), reason: 'one value decides it');
    expect(s.reliable(0.5), isTrue);
    expect(s.reliable(0.95), isTrue);
    expect(s.reliable(0.99), isFalse);
    expect(formatReport(analyse([])), isEmpty);
  });

  test('a fit counts estimates from quick probes for more', () {
    // On the line y = x, but for one estimate from a slow probe.
    final x = <double>[0, 1, 2, 3, 4];
    final y = <double>[0, 1, 2, 3, 14];
    final plain = LinearFit.of(x, y)!;
    final weighted = LinearFit.of(
      x,
      y,
      sigma: [0.001, 0.001, 0.001, 0.001, 1],
    )!;
    expect(plain.slope, closeTo(3, 1e-9));
    expect(weighted.slope, closeTo(1, 0.01));
    // Unusable error scales leave every estimate counting the same.
    expect(LinearFit.of(x, y, sigma: [0, 1, 1, 1, 1])!.slope, plain.slope);
    expect(
      LinearFit.of(x, y, sigma: [double.nan, 1, 1, 1, 1])!.slope,
      plain.slope,
    );
  });

  test('a device that received nothing from a sender is reported', () async {
    final a = await recorded(
      header('a', sourceId: 'A'),
      (w) => w
        ..sent(1, 0)
        ..received('A', 1, receivedClock: 0.001, sourceClock: 0)
        ..event(0, 'resolved', {
          'expected': 2,
          'found': ['A'],
        })
        ..event(1, 'receive_error', {'from': 'B', 'code': -3})
        ..event(2, 'receive_health', {'from': 'B', 'healthy': false})
        ..event(3, 'receive_health', {'from': 'B', 'healthy': true}),
    );
    final b = await recorded(header('b', sourceId: 'B'), (w) {
      for (var seq = 1; seq <= 50; seq++) {
        w.sent(seq, seq * 0.01);
      }
      w.received('A', 1, receivedClock: 5, sourceClock: 0, clockOffset: 5);
    });
    final run = analyse([a, b]).runs.single;
    final silent = run.pairs.firstWhere((p) => p.from == 'b' && p.to == 'a');
    expect(silent.received, 0);
    expect(silent.sent, 50);
    expect(silent.lost, 50);
    expect(silent.lostInterior, 0);
    expect(silent.lostEdges, 50);
    expect(silent.lossRate, 1);
    expect(silent.latency, isNull);
    // b did not get its own samples back, which not every transport does.
    expect(run.pairs.where((p) => p.from == 'b' && p.to == 'b'), isEmpty);
    expect(run.warnings, [
      'a received nothing from b, which sent 50.',
      'a found 1 of the 2 streams it expected; it received nothing from the '
          'rest.',
      'a stopped receiving from b during the run (error -3).',
      'a was interrupted 1 time(s) receiving from b: samples were late or '
          'missing for that, not for the network.',
    ]);
    final text = formatReport(Report([run]));
    expect(text, contains('! a received nothing from b'));
    expect(text, contains('received 0 of 50, lost 50 (100.000%)'));
  });

  test('loss at the ends of a run is told from loss within it', () async {
    final sender = await recorded(header('b', sourceId: 'B'), (w) {
      for (var seq = 1; seq <= 100; seq++) {
        w.sent(seq, seq * 0.01);
      }
    });
    final receiver = await recorded(header('a', sourceId: 'A'), (w) {
      // Listening from 11 to 95, and 50 never arrived.
      for (var seq = 11; seq <= 95; seq++) {
        if (seq == 50) continue;
        w.received(
          'B',
          seq,
          receivedClock: seq * 0.01 + 0.001,
          sourceClock: seq * 0.01,
          clockOffset: 0,
        );
      }
    });
    final pair = analyse([receiver, sender]).runs.single.pairs.single;
    expect(pair.lost, 16);
    expect(pair.lostInterior, 1);
    expect(pair.lostEdges, 15);
    expect(pair.interiorLossRate, closeTo(1 / 85, 1e-12));
    expect(
      formatReport(analyse([receiver, sender])),
      contains(': 1 while receiving, 15 before the first or after the last'),
    );
  });

  test(
    'an offset estimated for a device\'s own samples is not applied',
    () async {
      final log = await recorded(header('a', sourceId: 'A'), (w) {
        for (var k = 0; k < 5; k++) {
          w.clockSync(
            'A',
            receivedClock: 10.0 + k,
            offset: -0.0001 + k * 0.00002,
            remoteTime: 10.0 + k,
            uncertainty: 0.0001,
          );
        }
        for (var seq = 0; seq < 40; seq++) {
          w.received(
            'A',
            seq,
            receivedClock: 10 + seq * 0.1 + 0.0003,
            sourceClock: 10 + seq * 0.1,
            clockOffset: -0.0001,
            uncertainty: 0.0001,
          );
        }
      });
      final pair = analyse([log]).runs.single.pairs.single;
      expect(pair.loopback, isTrue);
      expect(pair.latency!.mean, closeTo(0.0003, 1e-9));
      expect(pair.latencyFitted!.mean, closeTo(0.0003, 1e-9));
      expect(pair.clock, isNull);
      expect(pair.uncertainty, isNull);
      expect(pair.series.clockOffset, everyElement(0));
      expect(formatReport(analyse([log])), isNot(contains('drift')));
    },
  );

  test('the two directions together do not depend on the offsets', () async {
    // b's clock is 1000 s ahead of a's. a -> b takes 3 ms and b -> a 1 ms,
    // but each device's estimate of the other's offset is out: a's by
    // +0.4 ms, b's by +0.2 ms.
    const errorAtA = 0.0004, errorAtB = 0.0002;
    Future<RunLog> device(
      String name,
      String other, {
      required double offset,
      required double latency,
    }) => recorded(header(name, sourceId: name.toUpperCase()), (w) {
      for (var seq = 0; seq < 200; seq++) {
        final t = seq * 0.01;
        w.sent(seq, t);
        // The other's clock when it sent, and this one's on arrival.
        w.received(
          other,
          seq,
          sourceClock: t,
          receivedClock: t + offset + latency,
          clockOffset: offset + (name == 'a' ? errorAtA : errorAtB),
          uncertainty: 0.002,
        );
      }
    });
    final a = await device('a', 'B', offset: -1000, latency: 0.001);
    final b = await device('b', 'A', offset: 1000, latency: 0.003);
    final run = analyse([a, b]).runs.single;
    final bToA = run.pairs.firstWhere((p) => p.to == 'a');
    final aToB = run.pairs.firstWhere((p) => p.to == 'b');
    expect(bToA.latency!.mean, closeTo(0.001 - errorAtA, 1e-9));
    expect(aToB.latency!.mean, closeTo(0.003 - errorAtB, 1e-9));
    final both = run.symmetry.single;
    expect((both.a, both.b), ('a', 'b'));
    expect(both.offsetInconsistency, closeTo(errorAtA + errorAtB, 1e-9));
    expect(both.latencyMean, closeTo(0.002, 1e-9));
    expect(both.latencyP50, closeTo(0.002, 1e-9));
    expect(formatReport(Report([run])), contains('a <-> b: 2.000 ms p50'));
  });

  test('runs are kept apart', () async {
    final one = await recorded(header('a', runId: 'r1'), (w) => w.sent(1, 0));
    final two = await recorded(header('a', runId: 'r2'), (w) => w.sent(1, 0));
    expect(analyse([one, two]).runs.map((r) => r.runId), ['r1', 'r2']);
  });
}
