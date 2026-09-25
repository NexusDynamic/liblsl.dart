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
