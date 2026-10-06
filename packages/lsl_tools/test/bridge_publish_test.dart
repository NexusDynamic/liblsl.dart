@Tags(['lsl'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:lsl_tools/lsl_tools.dart';
import 'package:test/test.dart';

Future<LslStreamDescription> _find(LslDiscovery d, String name) async {
  for (var i = 0; i < 100; i++) {
    final s = (await d.streams()).where((s) => s.name == name);
    if (s.isNotEmpty) return s.first;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('$name not found');
}

void main() {
  test('a client publishes streams as LSL outlets on the bridge', () async {
    final id = DateTime.now().microsecondsSinceEpoch;
    final server = await LslBridgeServer.start(
      const [],
      port: 0,
      token: 'k',
      acceptPublish: true,
    );
    final client = await LslBridgeClient.connect(
      Uri.parse('ws://127.0.0.1:${server.port}'),
      token: 'k',
    );
    await client.onStreams.first;
    expect(client.acceptsPublish, isTrue);
    final eeg = await client.publish(
      LslOutletSpec(
        name: 'published_$id',
        type: 'EEG',
        channelCount: 2,
        rate: 100,
        sourceId: 'pub_$id',
        channels: const [LslChannel('Fp1'), LslChannel('Fp2')],
      ),
    );
    final markers = await client.publish(
      LslOutletSpec(
        name: 'published_markers_$id',
        type: 'Markers',
        channelCount: 1,
        rate: 0,
        format: LslFormat.string,
        sourceId: 'pubm_$id',
      ),
    );
    expect(server.published, hasLength(2));
    final d = lsl.discover();
    const options = LslInletOptions(dejitter: false);
    final a = await lsl.openInlet(await _find(d, 'published_$id'), options);
    final b = await lsl.openInlet(
      await _find(d, 'published_markers_$id'),
      options,
    );
    expect(a.channels.map((c) => c.label), ['Fp1', 'Fp2']);
    expect(a.stream.rate, 100);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final t = lsl.clock();
    await eeg.push(
      Float32List.fromList([
        for (var i = 0; i < 100; i++) ...[i.toDouble(), -i.toDouble()],
      ]),
      Float64List.fromList([for (var i = 0; i < 100; i++) t + i / 100]),
    );
    await markers.pushStrings(['hello'], [t + 0.5]);
    final values = <double>[], times = <double>[], text = <String>[];
    for (var i = 0; i < 100 && (values.length < 200 || text.isEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final c = await a.pull(1000);
      values.addAll(c.values ?? const []);
      times.addAll(c.times);
      text.addAll((await b.pull(10)).strings ?? const []);
    }
    expect(values, [
      for (var i = 0; i < 100; i++) ...[i.toDouble(), -i.toDouble()],
    ]);
    // Same computer: the clocks agree to within the offset's precision.
    expect(times.first, closeTo(t, 0.01));
    expect(text, ['hello']);
    expect(server.received, 101);

    // Unpublished: the outlet goes away.
    await eeg.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.published, ['published_markers_$id']);
    await a.close();
    await b.close();
    d.close();
    await client.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // The client left: its streams are gone.
    expect(server.published, isEmpty);
    await server.close();
  });

  test('a bridge that does not accept streams refuses them', () async {
    final server = await LslBridgeServer.start(const [], port: 0);
    final client = await LslBridgeClient.connect(
      Uri.parse('ws://127.0.0.1:${server.port}'),
    );
    await client.onStreams.first;
    expect(client.acceptsPublish, isFalse);
    await expectLater(
      client.publish(
        const LslOutletSpec(
          name: 'refused',
          type: 'EEG',
          channelCount: 1,
          rate: 10,
          sourceId: 'refused',
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(server.published, isEmpty);
    await client.close();
    await server.close();
  });

  test('LSL to a bridge and back to LSL keeps the time stamps', () async {
    final id = DateTime.now().microsecondsSinceEpoch;
    final source = await lsl.createOutlet(
      LslOutletSpec(
        name: 'timed_$id',
        type: 'Markers',
        channelCount: 1,
        rate: 0,
        sourceId: 'timed_$id',
      ),
      const LslOutletOptions(),
    );
    final d = lsl.discover();
    final server = await LslBridgeServer.start(
      [await _find(d, 'timed_$id')],
      port: 0,
      host: '127.0.0.1',
    );
    final client = await LslBridgeClient.connect(
      Uri.parse('ws://127.0.0.1:${server.port}'),
      name: 'far',
    );
    final republisher = await LslBridgeRepublisher.start(
      client,
      suffix: '_far',
    );
    const options = LslInletOptions(dejitter: false);
    final inlet = await lsl.openInlet(
      await _find(d, 'timed_${id}_far'),
      options,
    );
    final timing = await lsl.openInlet(
      await _find(d, 'BridgeTiming_far'),
      options,
    );

    // Sample i is stamped sent[i]; all three clocks are this computer's.
    final sent = <double>[], got = <int, double>{}, reports = <String>[];
    for (var i = 0; i < 300 && (got.length < 50 || reports.isEmpty); i++) {
      if (sent.length < 50) {
        sent.add(lsl.clock());
        await source.push(
          Float32List.fromList([sent.length - 1.0]),
          Float64List.fromList([sent.last]),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final c = await inlet.pull(1000);
      for (var k = 0; k < c.length; k++) {
        got[c.values![k].round()] = c.times[k];
      }
      reports.addAll((await timing.pull(10)).strings ?? const []);
    }
    expect(got, hasLength(50));
    final chain = republisher.timing['timed_${id}_far']!;
    expect(chain.hops.map((h) => h.via), ['lsl', 'bridge']);
    expect(chain.hops.last.node, 'far');
    expect(chain.uncertainty, greaterThan(0));
    // The hops' bound, and LSL's own for the last step back into LSL.
    final bound = chain.uncertainty + 1e-3;
    for (var i = 0; i < 50; i++) {
      expect(got[i], closeTo(sent[i], bound));
    }
    expect(chain.offset.abs(), lessThan(bound));
    expect(chain.latency, inInclusiveRange(0, 1));

    // The same figures, for whoever records in the far lab.
    final report = jsonDecode(reports.last) as Map<String, Object?>;
    expect(report['stream'], 'timed_${id}_far');
    expect(report['hops'], hasLength(2));
    expect(report['uncertainty'], greaterThan(0));

    await inlet.close();
    await timing.close();
    d.close();
    await republisher.close();
    await client.close();
    await server.close();
    await source.close();
  });
}
