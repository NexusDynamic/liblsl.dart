import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:openbci_cyton/openbci_cyton.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:test/test.dart';

import 'package:openbci_cyton/testing.dart';

final _hasSocat =
    !Platform.isWindows &&
    Process.runSync('sh', ['-c', 'command -v socat']).exitCode == 0;

void main() {
  group('CytonDecoder', () {
    test('8 channels: µV, accelerometer, lost samples', () {
      final d = CytonDecoder();
      final bytes = <int>[
        0x42, 0x13, // junk before the first packet
        ...encodeCytonPacket(
          0,
          [1, -2, 3, -4, 5, -6, 7, -8],
          accel: [0.25, -0.5, 1],
        ),
        ...encodeCytonPacket(1, [100, 0, 0, 0, 0, 0, 0, -187500]),
        ...encodeCytonPacket(4, [0, 0, 0, 0, 0, 0, 0, 0]),
      ];
      final out = <CytonSample>[
        ...d.add(bytes.sublist(0, 30)),
        ...d.add(bytes.sublist(30)),
      ];
      expect(out, hasLength(3));
      final lsb = cytonMicrovolts(24);
      for (var i = 0; i < 8; i++) {
        expect(out[0].eeg[i], closeTo((i + 1) * (i.isEven ? 1 : -1), lsb));
      }
      expect(out[1].eeg[7], closeTo(-187500, lsb)); // full scale
      expect(out[0].accel[1], closeTo(-0.5, cytonAccelScale));
      // No new reading: the last one holds.
      expect(out[1].accel[2], closeTo(1, cytonAccelScale));
      expect(out[2].lost, 2);
    });

    test('16 channels: Daisy packets pair up', () {
      final d = CytonDecoder(daisy: true);
      final out = d.add([
        ...encodeCytonPacket(1, List.filled(8, 5)), // no pair: dropped
        ...encodeCytonPacket(2, [for (var i = 9; i <= 16; i++) i * 1.0]),
        ...encodeCytonPacket(3, [for (var i = 1; i <= 8; i++) i * 1.0]),
      ]);
      expect(out, hasLength(1));
      expect(out.single.eeg, hasLength(16));
      for (var i = 0; i < 16; i++) {
        expect(out.single.eeg[i], closeTo(i + 1.0, cytonMicrovolts(24)));
      }
      expect(d.dropped, 1);
    });

    test('gain scales channels', () {
      final d = CytonDecoder(gains: [1, ...List.filled(15, 24)]);
      final s = d
          .add(encodeCytonPacket(0, List.filled(8, 1000.0), gain: 1))
          .single;
      expect(s.eeg[0], closeTo(1000, cytonMicrovolts(1)));
    });

    test('channel command characters', () {
      expect(cytonChannelChar(1), '1');
      expect(cytonChannelChar(9), 'Q');
      expect(cytonChannelChar(16), 'I');
      expect(cytonChannelSwitch(1, true), '!');
      expect(cytonChannelSwitch(8, false), '8');
      expect(cytonChannelSwitch(9, true), 'Q');
      expect(cytonChannelSwitch(16, false), 'i');
    });

    test('markers (marker board mode)', () {
      final d = CytonDecoder(mode: CytonBoardMode.marker);
      final out = d.add([
        ...encodeCytonPacket(0, List.filled(8, 0), endByte: cytonEndAnalog),
        ...encodeCytonPacket(
          1,
          List.filled(8, 0),
          aux: [0, 0x58, 0, 0, 0, 0],
          endByte: cytonEndAnalog,
        ),
      ]);
      expect(out.map((s) => s.marker), [null, 0x58]);
      expect(out[1].aux, [0, 0x58, 0, 0, 0, 0]);
      // The accelerometer is off.
      expect(out[1].accel, [0, 0, 0]);
    });

    test('a marker in either packet of a Daisy pair', () {
      final d = CytonDecoder(daisy: true, mode: CytonBoardMode.marker);
      final marked = [0, 0x41, 0, 0, 0, 0];
      final out = d.add([
        ...encodeCytonPacket(
          2,
          List.filled(8, 0),
          aux: marked,
          endByte: cytonEndAnalog,
        ),
        ...encodeCytonPacket(3, List.filled(8, 0), endByte: cytonEndAnalog),
      ]);
      expect(out.single.marker, 0x41);
    });

    test('a marker outlives a lost packet', () {
      final d = CytonDecoder(daisy: true, mode: CytonBoardMode.marker);
      List<int> packet(int n, {int marker = 0}) => encodeCytonPacket(
        n,
        List.filled(8, 0),
        aux: [0, marker, 0, 0, 0, 0],
        endByte: cytonEndAnalog,
      );
      final out = d.add([
        ...packet(2, marker: 0x42), // its pair is garbled
        ...packet(3).sublist(10),
        ...packet(4),
        ...packet(5),
      ]);
      expect(out.single.marker, 0x42);
      expect(out.single.lost, 0); // the first sample: nothing to compare
    });

    test('a byte marker, extended with its sign', () {
      final d = CytonDecoder(mode: CytonBoardMode.marker);
      final s = d
          .add(
            encodeCytonPacket(
              0,
              List.filled(8, 0),
              aux: [0xFF, 0x81, 0, 0, 0, 0],
              endByte: cytonEndAnalog,
            ),
          )
          .single;
      expect(s.marker, 0x81);
    });

    test('safe markers', () {
      expect(cytonMarkerIsSafe(128), isTrue);
      expect(cytonMarkerIsSafe(239), isTrue);
      expect(cytonMarkerIsSafe(240), isFalse);
      expect(cytonMarkerIsSafe('f'.codeUnitAt(0)), isTrue);
      for (final c in 'AaSbsvd1!xX0-`~/'.codeUnits) {
        expect(cytonMarkerIsSafe(c), isFalse, reason: String.fromCharCode(c));
      }
      expect(cytonMarkerLabel('f'.codeUnitAt(0)), 'f');
      expect(cytonMarkerLabel(200), '200');
    });

    test('no markers in other modes', () {
      final d = CytonDecoder(mode: CytonBoardMode.analog);
      final s = d
          .add(
            encodeCytonPacket(
              0,
              List.filled(8, 0),
              aux: [0, 5, 0xFF, 0xFE, 1, 0],
              endByte: cytonEndAnalog,
            ),
          )
          .single;
      expect(s.marker, isNull);
      expect(s.analog, [5, -2, 256]);
    });

    test('changed gains rescale what follows', () {
      final gains = List.filled(16, 24);
      final d = CytonDecoder(gains: gains);
      final packet = encodeCytonPacket(0, List.filled(8, 100.0));
      expect(d.add(packet).single.eeg[0], closeTo(100, 0.01));
      gains[0] = 1;
      expect(d.add(packet).single.eeg[0], closeTo(2400, 0.5));
    });
  });

  group('settings', () {
    test('channel commands', () {
      expect(const CytonChannelSettings().commandFor(1), 'x1060110X');
      expect(CytonChannelSettings.bipolar.commandFor(3), 'x3060100X');
      expect(CytonChannelSettings.impedance.commandFor(9), 'xQ000100X');
      expect(
        const CytonChannelSettings(
          enabled: false,
          gain: 8,
          input: CytonInput.testSignal,
        ).commandFor(16),
        'xI145110X',
      );
      expect(
        () => const CytonChannelSettings(gain: 3).commandFor(1),
        throwsArgumentError,
      );
      expect(
        const CytonChannelSettings().copyWith(srb2: false),
        CytonChannelSettings.bipolar,
      );
    });

    test('sampling rates', () {
      expect(CytonSampleRate.nearest(254), CytonSampleRate.hz250);
      expect(CytonSampleRate.nearest(1010), CytonSampleRate.hz1000);
      expect(CytonSampleRate.nearest(100), CytonSampleRate.hz250);
      expect(CytonSampleRate.of(500), CytonSampleRate.hz500);
      expect(CytonSampleRate.of(300), isNull);
    });

    test('SD card space for a duration', () {
      expect(CytonSdDuration.forMinutes(3), CytonSdDuration.min5);
      expect(CytonSdDuration.forMinutes(5), CytonSdDuration.min15);
      expect(CytonSdDuration.forMinutes(120), CytonSdDuration.hour4);
      expect(
        CytonSdDuration.forMinutes(120, CytonSampleRate.hz1000),
        CytonSdDuration.hour12,
      );
      expect(
        () => CytonSdDuration.forMinutes(600, CytonSampleRate.hz1000),
        throwsArgumentError,
      );
    });
  });

  group('impedance', () {
    test('amplitude of the lead-off signal', () {
      for (final rate in [125.0, 250.0]) {
        final x = [
          for (var i = 0; i < 248; i++)
            1000 +
                50 * math.sin(2 * math.pi * cytonLeadOffHz * i / rate + 0.3) +
                5 * math.sin(2 * math.pi * 10 * i / rate),
        ];
        expect(toneAmplitude(x, rate), closeTo(50, 0.5), reason: '$rate Hz');
      }
    });

    test('ohms from the amplitude', () {
      // 6 nA through 10 kΩ and the 2.2 kΩ resistor: 73.2 µV.
      expect(cytonImpedanceOhms(73.2), closeTo(10000, 1e-6));
      expect(cytonImpedanceOhms(1), 0);
    });
  });

  group('over a pty pair', () {
    late Process socat;
    late String a, b;
    setUp(() async {
      final dir = Directory.systemTemp.createTempSync('cyton');
      a = '${dir.path}/a';
      b = '${dir.path}/b';
      socat = await Process.start('socat', [
        'pty,raw,echo=0,link=$a',
        'pty,raw,echo=0,link=$b',
      ]);
      for (var i = 0; i < 100 && !File(b).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    tearDown(() => socat.kill());

    test('connect, configure and stream a Cyton + Daisy', () async {
      final provider = SerialPortProvider.platform();
      final far = await provider.open(SerialPortInfo(id: a));
      final fake = FakeCyton(far);
      addTearDown(far.close);
      final board = await CytonBoard.connect(
        await provider.open(SerialPortInfo(id: b), baudRate: cytonBaudRate),
      );
      expect(board.daisy, isTrue);
      expect(board.channelCount, 16);
      expect(board.rate, 125);
      expect(board.info, contains('Firmware: v3.1.2'));
      await board.configureChannel(1, const CytonChannelSettings());
      await board.configureChannel(3, CytonChannelSettings.bipolar);
      await board.configureChannel(
        10,
        const CytonChannelSettings(gain: 8, srb1: true, srb2: false),
      );
      // The board's defaults are x1060110X (SRB2 before SRB1).
      expect(
        fake.received,
        containsAllInOrder(['x1060110X', 'x3060100X', 'xW040101X']),
      );
      expect(board.gains[9], 8);

      final samples = <CytonSample>[];
      board.samples.listen(samples.add);
      await board.start();
      for (var i = 0; i < 100 && samples.length < 125; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await board.stop();
      expect(samples.length, greaterThanOrEqualTo(125));
      expect(samples.every((s) => s.lost == 0), isTrue);
      // Channel c peaks at 10 × c µV.
      for (final ch in [1, 9, 16]) {
        final peak = samples.map((s) => s.eeg[ch - 1].abs()).reduce(math.max);
        expect(peak, closeTo(10.0 * ch, 0.5 * ch + 0.1), reason: 'ch $ch');
      }
      expect(samples.last.accel, [0, 0.5, 1]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fake.received, containsAllInOrder(['s', 'v', 'C', 'd', 'b', 's']));
      fake.stop();
      await board.close();
    });

    Future<(FakeCyton, CytonBoard)> connect({
      bool daisy = true,
      CytonSampleRate? sampleRate,
      CytonBoardMode? boardMode,
    }) async {
      final provider = SerialPortProvider.platform();
      final far = await provider.open(SerialPortInfo(id: a));
      final fake = FakeCyton(far, daisy: daisy);
      addTearDown(far.close);
      addTearDown(fake.stop);
      final board = await CytonBoard.connect(
        await provider.open(SerialPortInfo(id: b), baudRate: cytonBaudRate),
        sampleRate: sampleRate,
        boardMode: boardMode,
      );
      addTearDown(board.close);
      return (fake, board);
    }

    Future<List<CytonSample>> stream(CytonBoard board, int n) async {
      final samples = <CytonSample>[];
      final sub = board.samples.listen(samples.add);
      for (var i = 0; i < 200 && samples.length < n; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await sub.cancel();
      return samples;
    }

    test('sampling rate and board mode', () async {
      final (fake, board) = await connect();
      expect(board.sampleRate, CytonSampleRate.hz250);
      expect(board.boardMode, CytonBoardMode.defaults);
      expect(fake.received, containsAllInOrder(['d', '~~', '//']));
      await board.setSampleRate(CytonSampleRate.hz1000);
      expect(board.sampleRate, CytonSampleRate.hz1000);
      expect(board.live, isFalse);
      expect(await board.querySampleRate(), CytonSampleRate.hz1000);
      await board.setBoardMode(CytonBoardMode.analog);
      expect(await board.queryBoardMode(), CytonBoardMode.analog);
      expect(fake.received, containsAllInOrder(['~4', '~~', '/2', '//']));
      expect(await board.firmwareVersion(), 'v3.1.2');
      expect(await board.registers(), contains('CH1SET'));
    });

    test('set on connecting when given', () async {
      final (fake, board) = await connect(
        sampleRate: CytonSampleRate.hz250,
        boardMode: CytonBoardMode.marker,
      );
      expect(fake.received, containsAllInOrder(['d', '~6', '/4']));
      expect(fake.received, isNot(contains('~~')));
      expect(board.boardMode, CytonBoardMode.marker);
    });

    test('markers', () async {
      final (fake, board) = await connect(boardMode: CytonBoardMode.marker);
      // A is a command (log to the SD card) if the backtick is lost.
      await expectLater(
        () => board.marker('A'.codeUnitAt(0)),
        throwsArgumentError,
      );
      await expectLater(() => board.marker(0xF0), throwsArgumentError);
      await board.start();
      final collected = stream(board, 60);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // At once: the board holds one marker per sample.
      unawaited(board.marker('f'.codeUnitAt(0)));
      await board.marker(200);
      final samples = await collected;
      await board.stop();
      expect(samples.where((s) => s.marker != null).map((s) => s.marker), [
        'f'.codeUnitAt(0),
        200,
      ]);
    });

    test('channels while streaming: off, gain', () async {
      final (fake, board) = await connect(daisy: false);
      await board.start();
      await stream(board, 10);
      await board.setChannelEnabled(2, false);
      await board.configureChannel(3, const CytonChannelSettings(gain: 2));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final samples = await stream(board, 125);
      await board.stop();
      expect(fake.received, containsAllInOrder(['2', 'x3010110X']));
      expect(board.channels[1].enabled, isFalse);
      expect(board.gains[2], 2);
      final peak2 = samples.map((s) => s.eeg[1].abs()).reduce(math.max);
      final peak3 = samples.map((s) => s.eeg[2].abs()).reduce(math.max);
      expect(peak2, 0);
      // Still 30 µV: decoded at the new gain.
      expect(peak3, closeTo(30, 1));
    });

    test('test signal, and back', () async {
      final (fake, board) = await connect(daisy: false);
      await board.configureChannel(1, CytonChannelSettings.bipolar);
      await board.setTestSignal(CytonTestSignal.pulse1xSlow);
      expect(board.testSignal, CytonTestSignal.pulse1xSlow);
      expect(board.channels[0].input, CytonInput.testSignal);
      expect(board.channels[0].srb2, isFalse);
      await board.setTestSignal(null);
      expect(board.testSignal, isNull);
      expect(board.channels[0], CytonChannelSettings.bipolar);
      expect(
        fake.received,
        containsAllInOrder(['x1060100X', '-', 'x1060100X', 'x2060110X']),
      );
    });

    test('SD card recording', () async {
      final (fake, board) = await connect();
      final reply = await board.startSdRecording(CytonSdDuration.test);
      expect(reply, contains('OBCI_01.TXT'));
      expect(board.sdFile, 'OBCI_01.TXT');
      expect(board.streaming, isTrue);
      expect(await stream(board, 20), hasLength(greaterThanOrEqualTo(20)));
      final summary = await board.stopSdRecording();
      expect(summary, contains('SamplingRate'));
      expect(board.sdFile, isNull);
      expect(board.streaming, isFalse);
      expect(fake.received, containsAllInOrder(['a', 'b', 's', 'j']));
    });

    test('SD card recording above 250 Hz: no samples', () async {
      final (fake, board) = await connect();
      await board.setSampleRate(CytonSampleRate.hz1000);
      await board.startSdRecording(CytonSdDuration.min5);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        await stream(board, 1).timeout(const Duration(seconds: 5)),
        isEmpty,
      );
      // Closing closes the file.
      await board.close();
      expect(fake.received, containsAllInOrder(['A', 'b', 's', 'j']));
    });

    test('impedance', () async {
      final (fake, board) = await connect();
      fake.impedanceOhms = 25000;
      await board.configureChannel(2, CytonChannelSettings.bipolar);
      await expectLater(() => board.measureImpedance(1), throwsStateError);
      await board.start();
      final seen = <int>[];
      final ohms = await board.measureImpedances(
        channels: [2, 10],
        window: const Duration(seconds: 1),
        onChannel: (c, _) => seen.add(c),
      );
      await board.stop();
      expect(seen, [2, 10]);
      // The 10 Hz sine of the channel leaks a little.
      expect(ohms[2], closeTo(25000, 500));
      expect(ohms[10], closeTo(25000, 500));
      expect(
        fake.received,
        containsAllInOrder([
          'x2000100X',
          'z201Z',
          'z200Z',
          'x2060100X',
          'xW000100X',
          'zW01Z',
          'zW00Z',
          'xW060110X',
        ]),
      );
      expect(board.channels[1], CytonChannelSettings.bipolar);
    });

    test('without a Daisy: 8 channels at 250 Hz', () async {
      final provider = SerialPortProvider.platform();
      final far = await provider.open(SerialPortInfo(id: a));
      final fake = FakeCyton(far, daisy: false);
      addTearDown(far.close);
      final board = await CytonBoard.connect(
        await provider.open(SerialPortInfo(id: b), baudRate: cytonBaudRate),
      );
      expect(board.channelCount, 8);
      expect(board.rate, 250);
      expect(fake.received, isNot(contains('C')));
      fake.stop();
      await board.close();
    });
  }, skip: _hasSocat ? false : 'socat not available');
}
