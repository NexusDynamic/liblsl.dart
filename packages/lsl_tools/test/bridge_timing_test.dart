import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lsl_tools/lsl_tools.dart';
import 'package:test/test.dart';

/// Wait until [done], or fail.
Future<void> _until(bool Function() done, [String? what]) async {
  for (var i = 0; i < 300; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for ${what ?? 'a condition'}');
}

/// Everything [inlet] has, once it has at least [count] samples.
Future<List<double>> _times(LslInlet inlet, int count) async {
  final times = <double>[];
  var pulling = false;
  await _until(() {
    if (!pulling) {
      pulling = true;
      inlet.pull(1000).then((c) {
        times.addAll(c.times);
        pulling = false;
      });
    }
    return times.length >= count;
  }, 'samples');
  return times;
}

void main() {
  // Three computers whose clocks read nothing alike.
  final watch = Stopwatch()..start();
  double base() => watch.elapsedMicroseconds / 1e6;
  double onServer() => base() + 5000;
  double onA() => base() - 300;
  double onB() => base() + 77777;
  const aToB = 77777.0 + 300;

  late LslBridgeServer server;
  late Uri url;

  setUp(() async {
    server = await LslBridgeServer.start(
      const [],
      port: 0,
      host: '127.0.0.1',
      acceptPublish: true,
      localOutlets: false,
      clock: onServer,
    );
    url = Uri.parse('ws://127.0.0.1:${server.port}');
  });

  tearDown(() => server.close());

  Future<LslBridgeClient> connect(String name, double Function() clock) async {
    final c = await LslBridgeClient.connect(url, name: name, clock: clock);
    addTearDown(c.close);
    return c;
  }

  LslOutletSpec spec(String name, double rate) => LslOutletSpec(
    name: name,
    type: 'EEG',
    channelCount: 1,
    rate: rate,
    sourceId: name,
  );

  test(
    'time stamps cross clocks that disagree, with the way they came',
    () async {
      final a = await connect('a', onA);
      final b = await connect('b', onB);
      final c = await connect('c', onB);
      expect(a.link, isNull);
      await a.linked;
      // The bridge's clock is 5300 s ahead of A's: add −5300 to get A's.
      expect(a.link!.offset, closeTo(-5300, 0.01));
      expect(a.link!.uncertainty, greaterThan(0));

      final outlet = await a.publish(spec('irregular', 0));
      await _until(() => b.streams.isNotEmpty && c.streams.isNotEmpty);
      final synced = b.open(b.streams.single);
      final raw = c.open(
        c.streams.single,
        options: const LslInletOptions(clockSync: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Stamped on A's clock, the last one now.
      final t = onA();
      final sent = Float64List.fromList([
        for (var i = 0; i < 50; i++) t - (49 - i) / 100,
      ]);
      await outlet.push(Float32List(50), sent);

      // Corrected (the default): on B's clock, within the bound reported.
      final times = await _times(synced, 50);
      final chain = await synced.chain();
      final slack = chain.uncertainty + 2e-4;
      for (var i = 0; i < 50; i++) {
        expect(times[i], closeTo(sent[i] + aToB, slack));
      }
      expect((await synced.timeCorrectionEx()).offset, 0);

      // One hop to the bridge and one from it, each with its own bound.
      expect(chain.hops.map((h) => h.via), ['bridge', 'bridge']);
      expect(chain.hops.map((h) => h.node), ['127.0.0.1', 'b']);
      expect(chain.hops.every((h) => h.uncertainty > 0), isTrue);
      expect(chain.offset, closeTo(aToB, slack));
      expect(chain.latency, inInclusiveRange(-slack, 0.5));

      // Raw: as A stamped them, with the correction beside them, as LSL
      // gives it.
      expect(await _times(raw, 50), sent);
      final correction = await raw.timeCorrectionEx();
      expect(correction.offset, closeTo(aToB, slack));
      expect(correction.uncertainty, greaterThan(0));
      expect(correction.remoteTime, sent.last);

      // The bridge adds how long samples took to reach it.
      var later = chain;
      await _until(() {
        synced.chain().then((c) => later = c);
        return later.hops.first.latency != null;
      }, 'the latency at the bridge');
      expect(later.hops.first.latency, inInclusiveRange(-slack, 0.5));
      expect(later.hops.last.latency, greaterThanOrEqualTo(-slack));
    },
  );

  test('a regular stream is dejittered unless asked not to', () async {
    final a = await connect('a', onA);
    final b = await connect('b', onB);
    final c = await connect('c', onB);
    final outlet = await a.publish(spec('regular', 100));
    await _until(() => b.streams.isNotEmpty && c.streams.isNotEmpty);
    final smooth = b.open(b.streams.single);
    final plain = c.open(
      c.streams.single,
      options: const LslInletOptions(dejitter: false),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 100 Hz, each stamp up to 2 ms early or late.
    final t = onA() - 3;
    final truth = [for (var i = 0; i < 300; i++) t + i / 100];
    final sent = Float64List.fromList([
      for (var i = 0; i < 300; i++) truth[i] + (i.isEven ? 2e-3 : -2e-3),
    ]);
    await outlet.push(Float32List(300), sent);

    double error(List<double> times, List<double> against) {
      var sum = 0.0;
      for (var i = 150; i < 300; i++) {
        sum += (times[i] - against[i] - aToB).abs() / 150;
      }
      return sum;
    }

    final bound = (await smooth.chain()).uncertainty + 2e-4;
    expect(error(await _times(plain, 300), sent), lessThan(bound));
    expect(error(await _times(smooth, 300), truth), lessThan(bound + 5e-4));
  });

  test('samples wait for the clocks rather than arrive uncorrected', () async {
    final a = await connect('a', onA);
    final outlet = await a.publish(spec('early', 0));
    // B subscribes before it has measured anything.
    final b = await connect('b', onB);
    await _until(() => b.streams.isNotEmpty);
    final inlet = b.open(b.streams.single);
    expect(b.link, isNull);
    await expectLater(inlet.chain(), throwsStateError);
    await _until(() => server.clients.any((c) => c.subscriptions == 1));
    final t = onA();
    await outlet.push(Float32List(1), Float64List.fromList([t]));
    final times = await _times(inlet, 1);
    expect(times.single, closeTo(t + aToB, 0.01));
  });

  test('a client of the old protocol is turned away', () async {
    final old = await WebSocket.connect('$url');
    final messages = await old.toList();
    expect(messages, isEmpty);
    expect(old.closeCode, 4002);
    expect(old.closeReason, contains('protocol 2'));
  });
}
