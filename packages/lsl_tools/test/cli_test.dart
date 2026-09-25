@Tags(['lsl'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lsl_tools/cli.dart';
import 'package:lsl_tools/lsl_tools.dart';
import 'package:openbci_cyton/testing.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:test/test.dart';
import 'package:xdf/xdf.dart';

/// The first stream named [name] on the network.
Future<LslStreamDescription> _find(LslDiscovery d, String name) async {
  for (var i = 0; i < 100; i++) {
    final s = (await d.streams()).where((s) => s.name == name);
    if (s.isNotEmpty) return s.first;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('$name not found');
}

/// Whether `socat` can create a virtual serial port pair here.
final _hasSocat =
    !Platform.isWindows &&
    Process.runSync('sh', ['-c', 'command -v socat']).exitCode == 0;

void main() {
  final id = DateTime.now().microsecondsSinceEpoch;
  final dir = Directory.systemTemp.createTempSync('lsl_cli');
  tearDownAll(() => dir.deleteSync(recursive: true));

  test('list, and record a generated stream to XDF', () async {
    final g = await LslSignalGenerator.start(
      name: 'cli_gen_$id',
      channels: 2,
      rate: 100,
      noise: 0,
    );
    addTearDown(g.close);
    final listed = StringBuffer();
    expect(await runLslCli(['list', '--wait', '1'], out: listed), 0);
    expect(listed.toString(), contains('cli_gen_$id'));

    final path = '${dir.path}/rec.xdf';
    final out = StringBuffer();
    final code = await runLslCli([
      'record',
      path,
      '-s',
      'cli_gen_$id',
      '-d',
      '1.5',
    ], out: out);
    expect(code, 0, reason: '$out');
    final rec = loadXdf(File(path).readAsBytesSync());
    final s = rec.stream('cli_gen_$id')!;
    expect(s.info.channelCount, 2);
    expect(s.length, inInclusiveRange(120, 180));
    expect(s.effectiveRate, closeTo(100, 1));
  });

  test('share and bridge: a stream published again elsewhere', () async {
    final g = await LslSignalGenerator.start(
      name: 'cli_share_$id',
      channels: 3,
      rate: 200,
    );
    addTearDown(g.close);
    final stopShare = Completer<void>(), stopBridge = Completer<void>();
    final shareOut = StringBuffer();
    final sharing = runLslCli(
      ['share', '-s', 'cli_share_$id', '-p', '0', '--token', 't'],
      stop: stopShare.future,
      out: shareOut,
    );
    String? port;
    for (var i = 0; i < 100 && port == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      port = RegExp(r'on port (\d+)').firstMatch('$shareOut')?.group(1);
    }
    expect(port, isNotNull, reason: '$shareOut');
    final bridging = runLslCli(
      [
        'bridge',
        'ws://127.0.0.1:$port',
        '--token',
        't',
        '--suffix',
        '_bridged',
      ],
      stop: stopBridge.future,
      out: StringBuffer(),
    );
    final d = lsl.discover();
    final inlet = await lsl.openInlet(
      await _find(d, 'cli_share_${id}_bridged'),
      const LslInletOptions(dejitter: false),
    );
    expect(inlet.stream.channelCount, 3);
    expect(inlet.stream.rate, 200);
    var received = 0;
    for (var i = 0; i < 100 && received < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      received += (await inlet.pull(1000)).length;
    }
    expect(received, greaterThanOrEqualTo(200));
    await inlet.close();
    d.close();
    stopBridge.complete();
    stopShare.complete();
    expect(await bridging, 0);
    expect(await sharing, 0);
  });

  test('relay: a stream a client publishes reaches LSL elsewhere', () async {
    final stopRelay = Completer<void>(), stopBridge = Completer<void>();
    final relayOut = StringBuffer(), bridgeOut = StringBuffer();
    final relaying = runLslCli(
      ['relay', '-p', '0', '--host', '127.0.0.1'],
      stop: stopRelay.future,
      out: relayOut,
    );
    String? port;
    for (var i = 0; i < 100 && port == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      port = RegExp(r'on port (\d+)').firstMatch('$relayOut')?.group(1);
    }
    expect(port, isNotNull, reason: '$relayOut');
    final url = Uri.parse('ws://127.0.0.1:$port');
    // The bridge starts before anything is published, and follows.
    final bridging = runLslCli(
      ['bridge', '$url', '--suffix', '_relayed'],
      stop: stopBridge.future,
      out: bridgeOut,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final client = await LslBridgeClient.connect(url);
    final outlet = await client.publish(
      LslOutletSpec(
        name: 'cli_relay_$id',
        type: 'EEG',
        channelCount: 2,
        rate: 100,
        sourceId: 'cli_relay_$id',
      ),
    );
    final d = lsl.discover();
    final inlet = await lsl.openInlet(
      await _find(d, 'cli_relay_${id}_relayed'),
      const LslInletOptions(dejitter: false),
    );
    expect(inlet.stream.channelCount, 2);
    var received = 0;
    for (var i = 0; i < 150 && received < 100; i++) {
      final t = lsl.clock();
      await outlet.push(
        Float32List.fromList([1, 2, 3, 4]),
        Float64List.fromList([t, t + 0.01]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      received += (await inlet.pull(1000)).length;
    }
    expect(received, greaterThanOrEqualTo(100), reason: '$bridgeOut');
    expect('$bridgeOut', contains('Publishing cli_relay_${id}_relayed'));
    await inlet.close();
    d.close();
    await client.close();
    stopBridge.complete();
    stopRelay.complete();
    expect(await bridging, 0);
    expect(await relaying, 0);
  });

  test('publish: streams from here reach a relay\'s clients', () async {
    final g = await LslSignalGenerator.start(
      name: 'cli_pub_$id',
      channels: 2,
      rate: 100,
    );
    addTearDown(g.close);
    final server = await LslBridgeServer.start(
      const [],
      port: 0,
      acceptPublish: true,
      localOutlets: false,
    );
    addTearDown(server.close);
    final url = Uri.parse('ws://127.0.0.1:${server.port}');
    final stop = Completer<void>();
    final out = StringBuffer();
    final publishing = runLslCli(
      ['publish', '$url', '-s', 'cli_pub_$id'],
      stop: stop.future,
      out: out,
    );
    final viewer = await LslBridgeClient.connect(url);
    BridgeStream? shared;
    for (var i = 0; i < 150 && shared == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      shared = viewer.streams
          .where((s) => s.description.name == 'cli_pub_$id')
          .firstOrNull;
    }
    expect(shared, isNotNull, reason: '$out');
    expect(shared!.description.channelCount, 2);
    final inlet = viewer.open(shared);
    var received = 0;
    for (var i = 0; i < 150 && received < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      received += (await inlet.pull(1000)).length;
    }
    expect(received, greaterThanOrEqualTo(100));
    await viewer.close();
    stop.complete();
    expect(await publishing, 0);
  });

  test('replay an XDF file', () async {
    final path = '${dir.path}/replay.xdf';
    final w = XdfWriter(File(path).openWrite());
    w.addStream(
      1,
      XdfStreamInfo(
        name: 'cli_replay_$id',
        type: 'EEG',
        channelCount: 1,
        nominalRate: 100,
      ),
    );
    w.writeSamples(
      1,
      [for (var i = 0; i < 500; i++) 10 + i / 100],
      [for (var i = 0; i < 500; i++) i.toDouble()],
    );
    await w.close();
    final replaying = runLslCli(['replay', path], out: StringBuffer());
    final d = lsl.discover();
    final inlet = await lsl.openInlet(
      await _find(d, 'cli_replay_$id'),
      const LslInletOptions(dejitter: false),
    );
    final values = <double>[];
    var done = false;
    unawaited(
      replaying.then((code) {
        expect(code, 0);
        done = true;
      }),
    );
    while (!done) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final c = await inlet.pull(1000);
      values.addAll(c.values ?? const []);
    }
    // The inlet joined after the first samples went out.
    expect(values.length, greaterThan(100));
    expect(values.last, 499);
    await inlet.close();
    d.close();
  });

  test('publish a (simulated) OpenBCI Cyton', () async {
    final a = '${dir.path}/cyton_a', b = '${dir.path}/cyton_b';
    final socat = await Process.start('socat', [
      'pty,raw,echo=0,link=$a',
      'pty,raw,echo=0,link=$b',
    ]);
    addTearDown(socat.kill);
    for (var i = 0; i < 100 && !File(b).existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final far = await SerialPortProvider.platform().open(SerialPortInfo(id: a));
    final fake = FakeCyton(far);
    addTearDown(far.close);
    final stop = Completer<void>();
    final out = StringBuffer();
    final running = runLslCli(
      ['cyton', b, '--name', 'cyton_$id', '--bipolar', '9'],
      stop: stop.future,
      out: out,
    );
    final d = lsl.discover();
    final inlet = await lsl.openInlet(
      await _find(d, 'cyton_$id'),
      const LslInletOptions(dejitter: false),
    );
    expect(inlet.stream.channelCount, 16);
    expect(inlet.stream.rate, 125);
    expect(inlet.channels.first.label, 'Fp1');
    var received = 0;
    for (var i = 0; i < 100 && received < 125; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      received += (await inlet.pull(1000)).length;
    }
    expect(received, greaterThanOrEqualTo(125));
    expect(fake.received, contains('xQ060100X'));
    await inlet.close();
    d.close();
    stop.complete();
    expect(await running, 0, reason: '$out');
    fake.stop();
  }, skip: _hasSocat ? false : 'socat not available');
}
