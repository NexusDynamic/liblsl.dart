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
