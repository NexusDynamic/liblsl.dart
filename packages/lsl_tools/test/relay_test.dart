import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lsl_tools/lsl_tools.dart';
import 'package:test/test.dart';

/// Wait until [done], or fail.
Future<void> _until(bool Function() done, [String? what]) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for ${what ?? 'a condition'}');
}

void main() {
  late LslBridgeServer server;
  late Uri url;

  setUp(() async {
    // A relay without LSL: nothing shared from here, no outlets.
    server = await LslBridgeServer.start(
      const [],
      port: 0,
      host: '127.0.0.1',
      token: 'k',
      acceptPublish: true,
      localOutlets: false,
      allowedOrigins: const ['https://viewer.example'],
    );
    url = Uri.parse('ws://127.0.0.1:${server.port}');
  });

  tearDown(() => server.close());

  test('what one client publishes, another receives', () async {
    final a = await LslBridgeClient.connect(url, token: 'k');
    final b = await LslBridgeClient.connect(url, token: 'k');
    addTearDown(a.close);
    addTearDown(b.close);
    await _until(() => server.clientCount == 2, 'clients');
    expect(server.clients.map((c) => c.address), everyElement('127.0.0.1'));

    final outlet = await a.publish(
      const LslOutletSpec(
        name: 'relayed',
        type: 'EEG',
        channelCount: 2,
        rate: 100,
        sourceId: 'relay_test',
        channels: [
          LslChannel('C3', unit: 'microvolts'),
          LslChannel('C4'),
        ],
      ),
    );
    expect(server.published, ['relayed']);

    // B is told about it; A knows it is its own.
    await _until(() => b.streams.isNotEmpty, 'the stream list update');
    final shared = b.streams.single;
    expect(shared.description.name, 'relayed');
    expect(shared.channels.map((c) => c.label), ['C3', 'C4']);
    expect(shared.channels.first.unit, 'microvolts');
    await _until(() => a.ownIds.contains(shared.id), 'own ids');
    expect(a.others, isEmpty);
    expect(b.others, hasLength(1));

    final inlet = b.open(shared);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final t = lsl.clock();
    await outlet.push(
      Float32List.fromList([
        for (var i = 0; i < 50; i++) ...[i + 0.0, -i + 0.0],
      ]),
      Float64List.fromList([for (var i = 0; i < 50; i++) t + i / 100]),
    );
    final values = <double>[], times = <double>[];
    await _until(() {
      inlet.pull(1000).then((c) {
        values.addAll(c.values ?? const []);
        times.addAll(c.times);
      });
      return values.length >= 100;
    }, 'samples');
    expect(values.take(4), [0, 0, 1, -1]);
    // Both clients are on this computer: the time stamps come back as sent.
    expect(times.first, closeTo(t, 0.05));
    expect(server.received, 50);

    // Unpublished: gone for B, and its inlet ends.
    await outlet.close();
    await _until(() => b.streams.isEmpty, 'the stream to go');
    expect(server.published, isEmpty);
    await expectLater(inlet.pull(10), throwsStateError);
  });

  test('values keep their stream\'s format through a relay', () async {
    final a = await LslBridgeClient.connect(url, token: 'k');
    final b = await LslBridgeClient.connect(url, token: 'k');
    addTearDown(a.close);
    addTearDown(b.close);
    LslOutletSpec spec(String name, LslFormat format, int channels) =>
        LslOutletSpec(
          name: name,
          type: 'Test',
          channelCount: channels,
          rate: 0,
          format: format,
          sourceId: 'relay_$name',
        );
    final doubles = await a.publish(spec('doubles', LslFormat.double64, 2));
    final longs = await a.publish(spec('longs', LslFormat.int64, 1));
    final words = await a.publish(spec('words', LslFormat.string, 3));
    await _until(() => b.streams.length == 3, 'the streams');
    BridgeStream named(String n) =>
        b.streams.singleWhere((s) => s.description.name == n);
    expect(named('doubles').description.format, LslFormat.double64);
    expect(named('longs').description.format, LslFormat.int64);
    expect(named('words').description.channelCount, 3);
    final inlets = {
      for (final n in ['doubles', 'longs', 'words']) n: b.open(named(n)),
    };
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final t = Float64List.fromList([lsl.clock()]);
    const d = [1 / 3, -1e-300];
    const big = (1 << 60) + 1;
    await doubles.push(Float64List.fromList(d), t);
    await longs.push(Int64List.fromList([big]), t);
    await words.pushStrings(['x', 'y', 'z'], t);

    final got = <String, LslChunk>{};
    await _until(() {
      for (final MapEntry(:key, :value) in inlets.entries) {
        value.pull(10).then((c) {
          if (c.length > 0) got[key] = c;
        });
      }
      return got.length == 3;
    }, 'samples');
    expect(got['doubles']!.values, d);
    expect(got['longs']!.typed, [big]);
    expect(got['words']!.strings, ['x', 'y', 'z']);
  });

  test('a client leaving takes its streams with it', () async {
    final a = await LslBridgeClient.connect(url, token: 'k');
    final b = await LslBridgeClient.connect(url, token: 'k');
    addTearDown(b.close);
    var updates = 0;
    final sub = server.onChange.listen((_) => updates++);
    addTearDown(sub.cancel);
    await a.publish(
      const LslOutletSpec(
        name: 'markers',
        type: 'Markers',
        channelCount: 1,
        rate: 0,
        format: LslFormat.string,
        sourceId: 'relay_markers',
      ),
    );
    await _until(() => b.streams.length == 1, 'the stream');
    await a.close();
    await _until(() => b.streams.isEmpty, 'the stream to go');
    expect(server.clientCount, 1);
    expect(updates, greaterThanOrEqualTo(2));
  });

  test('a wrong token or origin is refused', () async {
    await expectLater(
      LslBridgeClient.connect(url, token: 'wrong'),
      throwsA(anything),
    );
    final http = HttpClient();
    addTearDown(http.close);
    Future<int> get(Map<String, String> headers) async {
      final r = await http.getUrl(
        url.replace(scheme: 'http', queryParameters: {'token': 'k'}),
      );
      headers.forEach(r.headers.set);
      final res = await r.close();
      await res.drain<void>();
      return res.statusCode;
    }

    expect(await get({}), 200);
    expect(await get({'origin': 'https://viewer.example'}), 200);
    expect(await get({'origin': 'https://elsewhere.example'}), 403);
  });
}
