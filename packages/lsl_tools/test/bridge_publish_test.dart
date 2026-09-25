@Tags(['lsl'])
library;

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
}
