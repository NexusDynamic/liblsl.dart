import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbci_cyton/openbci_cyton.dart';
import 'package:openbci_cyton/testing.dart';
import 'package:openbci_cyton/xdf.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_serial/signal_viewer_serial.dart';
import 'package:signal_viewer_xdf/signal_viewer_xdf.dart';

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

  test('an OpenBCI Cyton + Daisy: EEG and accelerometer tabs', () async {
    final dir = Directory.systemTemp.createTempSync('cyton_session');
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
    final far = await provider.open(SerialPortInfo(id: a));
    final fake = FakeCyton(far);
    addTearDown(far.close);
    final session = await CytonSession.open(provider, SerialPortInfo(id: b));
    for (var i = 0; i < 100 && session.received < 125; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final eeg = session.streams[0], acc = session.streams[1];
    expect(eeg.channelCount, 16);
    expect(eeg.rate, 125);
    expect(eeg.labels.take(3), ['Fp1', 'Fp2', 'C3']);
    expect(eeg.kind, Kind.eeg);
    expect(acc.labels, ['x', 'y', 'z']);
    final w = (await LiveStreamSource(
      session,
      eeg,
    ).read(session.now - 1, session.now, DerivedSpec.none))!;
    // Channel 16 peaks at 160 µV.
    final peak = w.channels[15]
        .where((v) => !v.isNaN)
        .map((v) => v.abs())
        .reduce((x, y) => x > y ? x : y);
    expect(peak, closeTo(160, 5));
    expect(session.lostSampleCount, 0);
    fake.stop();
    await session.close();
  }, skip: hasSocat ? false : 'socat not available');

  group('a Cyton session', () {
    late String a, b;
    setUp(() async {
      final dir = Directory.systemTemp.createTempSync('cyton_session');
      a = '${dir.path}/a';
      b = '${dir.path}/b';
      final socat = await Process.start('socat', [
        'pty,raw,echo=0,link=$a',
        'pty,raw,echo=0,link=$b',
      ]);
      addTearDown(socat.kill);
      for (var i = 0; i < 100 && !File(b).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });

    Future<(FakeCyton, CytonSession)> open({bool markers = false}) async {
      final provider = SerialPortProvider.platform();
      final far = await provider.open(SerialPortInfo(id: a));
      final fake = FakeCyton(far);
      addTearDown(far.close);
      addTearDown(fake.stop);
      final session = await CytonSession.open(
        provider,
        SerialPortInfo(id: b),
        markers: markers,
      );
      addTearDown(session.close);
      return (fake, session);
    }

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('channels used for EMG get a tab of their own', () async {
      final (fake, session) = await open();
      await until(() => session.received > 0);
      expect(session.streams.map((s) => s.key), ['cyton:eeg', 'cyton:accel']);
      session.setRole(9, Kind.emg);
      session.setRole(10, Kind.emg);
      final emg = session.streams.firstWhere((s) => s.kind == Kind.emg);
      expect(emg.labels, ['F7', 'F8']);
      expect(emg.channels.map((c) => c.channel), [8, 9]);
      final eeg = session.streams.firstWhere((s) => s.kind == Kind.eeg);
      expect(eeg.key, 'cyton:eeg:1,2,3,4,5,6,7,8,11,12,13,14,15,16');
      expect(eeg.channelCount, 14);
    });

    test('markers', () async {
      final (fake, session) = await open(markers: true);
      await until(() => session.received > 20);
      expect(session.streams.map((s) => s.key), ['cyton:eeg', 'cyton:markers']);
      await session.marker('f'.codeUnitAt(0));
      await session.marker(130);
      await until(() => session.markerCount >= 2);
      final markers = session.streams.last;
      final events = LiveStreamSource(session, markers).events();
      expect(events.text!.single, ['f', '130']);
      expect(events.markers, isTrue);
      expect(events.times.last, lessThanOrEqualTo(session.now));
    });

    test('a pause leaves a gap', () async {
      final (fake, session) = await open();
      await until(() => session.received > 20);
      await session.pause();
      expect(session.titleSuffix, ' (paused)');
      final before = session.now;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final n = session.received;
      await session.resume();
      await until(() => session.received > n + 20);
      // The time axis kept going while paused.
      expect(session.now - before, greaterThan(0.5));
      expect(session.lostSampleCount, 0);
      final w = (await LiveStreamSource(
        session,
        session.streams.first,
      ).read(before, before + 0.4, DerivedSpec.none))!;
      expect(w.channels[0].where((v) => v.isNaN), isNotEmpty);
    });

    test('SD card recording', () async {
      final (fake, session) = await open();
      await until(() => session.received > 0);
      final reply = await session.startSd(
        CytonSdDuration.min5,
        CytonSampleRate.hz1000,
      );
      expect(reply, contains('OBCI_01.TXT'));
      expect(session.describe(), contains('no live data above 250 Hz'));
      expect(session.live, isFalse);
      await session.stopSd();
      expect(session.board.sampleRate, CytonSampleRate.hz250);
      expect(session.live, isTrue);
      expect(fake.received, containsAllInOrder(['~4', 'A', 'b', 's', 'j']));
      await until(() => fake.received.last == 'b');
      expect(fake.received.last, 'b');
    });
  }, skip: hasSocat ? false : 'socat not available');

  test('an SD card recording opens as XDF', () async {
    final bytes = File(
      '../openbci_cyton/test/fixtures/OBCI_23_head.TXT',
    ).readAsBytesSync();
    final out = BytesBuilder();
    await convertCytonSdToXdf(Stream.value(bytes), _Collect(out));
    final session = await XdfSession.open(
      'OBCI_23.TXT',
      ByteSourceSpec.bytes(out.takeBytes()),
    );
    addTearDown(session.close);
    for (var i = 0; i < 100 && session.streams.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(session.streams.map((s) => s.channelCount), [16, 3]);
    expect(session.streams.first.rate, 250);
  });
}

class _Collect implements Sink<List<int>> {
  final BytesBuilder out;
  _Collect(this.out);

  @override
  void add(List<int> data) => out.add(data);

  @override
  void close() {}
}
