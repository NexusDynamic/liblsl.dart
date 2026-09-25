import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_serial/signal_viewer_serial.dart';

void main() {
  group('SerialLineParser', () {
    test('numbers, headers and name:value pairs', () {
      final p = SerialLineParser();
      final lines = p.add(
        'ax ay az\r\n1,2,3\n4;5;6\n7\t8 9\nhello 1\n'.codeUnits,
      );
      expect(lines, hasLength(4));
      expect((lines[0] as SerialLabels).labels, ['ax', 'ay', 'az']);
      expect((lines[1] as SerialValues).values, [1, 2, 3]);
      expect((lines[2] as SerialValues).values, [4, 5, 6]);
      expect((lines[3] as SerialValues).values, [7, 8, 9]);
      final pairs = SerialLineParser.parse('x:1.5 y:-2');
      expect((pairs! as SerialLabels).labels, ['x', 'y']);
      expect((pairs as SerialValues).values, [1.5, -2]);
    });

    test('lines split across reads', () {
      final p = SerialLineParser();
      expect(p.add('1,2'.codeUnits), isEmpty);
      final l = p.add(',3\n'.codeUnits);
      expect((l.single as SerialValues).values, [1, 2, 3]);
    });
  });

  final hasSocat =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v socat']).exitCode == 0;

  test('a device writing lines becomes a live stream', () async {
    final dir = Directory.systemTemp.createTempSync('serial_stream');
    final a = '${dir.path}/a', b = '${dir.path}/b';
    final socat = await Process.start('socat', [
      'pty,raw,echo=0,link=$a',
      'pty,raw,echo=0,link=$b',
    ]);
    addTearDown(socat.kill);
    for (var i = 0; i < 100 && !File(b).existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final provider = SerialPortProvider.platform();
    final device = await provider.open(SerialPortInfo(id: a));
    addTearDown(device.close);
    final session = await SerialStreamSession.open(
      provider,
      SerialPortInfo(id: b),
      name: 'Arduino',
      baudRate: 115200,
      rate: 100,
      type: 'MoCap',
    );
    await device.write('x y\n'.codeUnits);
    // 100 samples at 100 Hz, in real time.
    for (var i = 0; i < 100; i++) {
      await device.write('$i,${-i}\n'.codeUnits);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (var i = 0; i < 50 && session.received < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(session.received, 100);
    final info = session.streams.single;
    expect(info.labels, ['x', 'y']);
    expect(info.rate, 100);
    expect(info.kind, Kind.imu);
    final w = (await LiveStreamSource(
      session,
      info,
    ).read(session.now - 0.5, session.now, DerivedSpec.none))!;
    final last = w.channels[0].lastIndexWhere((v) => !v.isNaN);
    expect(w.channels[0][last], 99);
    expect(w.channels[1][last], -99);
    await session.close();
  }, skip: hasSocat ? false : 'socat not available');
}
