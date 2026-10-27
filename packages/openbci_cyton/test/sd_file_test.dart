import 'dart:io';
import 'dart:typed_data';

import 'package:openbci_cyton/openbci_cyton.dart';
import 'package:openbci_cyton/xdf.dart';
import 'package:xdf/xdf.dart';
import 'package:test/test.dart';

void main() {
  // The start of a Cyton + Daisy recording at 250 Hz (firmware
  // v3.1.2-freeSD), with a line cut off and the unused space after it.
  final bytes = File('test/fixtures/OBCI_23_head.TXT').readAsBytesSync();

  test('a Cyton + Daisy recording', () {
    final f = CytonSdFile.parse(bytes);
    expect(f.channelCount, 16);
    expect(f.hasAccel, isTrue);
    expect(f.markers, isEmpty);
    expect(f.length, 300);
    expect(f.rate, 250);
    expect(f.rateEstimated, isTrue);
    expect(f.lost, 0);
    expect(f.skipped, 1); // the line cut off
    expect(f.metadata, {'STOP AT': '00006617'});
    expect(f.times[1], closeTo(1 / 250, 1e-12));
    final lsb = cytonMicrovolts(24);
    // 800000 is full scale (railed), B3E932 is -4986574.
    expect(f.eeg[0], closeTo(-0x800000 * lsb, 1e-6));
    expect(f.eeg[1], closeTo((0xB3E932 - 0x1000000) * lsb, 1e-6));
    // The first line has the accelerometer: 0000, 0E50, 04A0.
    expect(f.accel.sublist(0, 3), [
      0,
      0xE50 * cytonAccelScale,
      0x4A0 * cytonAccelScale,
    ]);
    // It holds until the next reading.
    expect(f.accel.sublist(3, 6), f.accel.sublist(0, 3));
  });

  test('given rate and gains', () {
    final f = CytonSdFile.parse(
      bytes,
      rate: 1000,
      gains: [1, ...List.filled(15, 24)],
    );
    expect(f.rate, 1000);
    expect(f.rateEstimated, isFalse);
    expect(
      f.eeg[1],
      closeTo((0xB3E932 - 0x1000000) * cytonMicrovolts(24), 1e-6),
    );
    expect(f.eeg[0], closeTo(-0x800000 * cytonMicrovolts(1), 1e-6));
  });

  test('8 channels, lost samples, estimated rate', () {
    String row(int n, {bool accel = false}) => [
      n.toRadixString(16).toUpperCase().padLeft(2, '0'),
      for (var c = 0; c < 8; c++) '000064',
      if (accel) ...['0010', '0020', '0030'],
    ].join(',');
    // 1000 Hz: an accelerometer reading every 40 samples.
    final lines = [
      for (var i = 0; i < 400; i++)
        if (i != 7 && i != 8) row(i % 256, accel: i % 40 == 0),
    ];
    final f = CytonSdFile.parse('${lines.join('\r\n')}\r\n'.codeUnits);
    expect(f.channelCount, 8);
    expect(f.rate, 1000);
    expect(f.lost, 2);
    expect(f.times[7], closeTo(9 / 1000, 1e-12));
    expect(f.eeg[0], closeTo(100 * cytonMicrovolts(24), 1e-9));
  });

  test('markers', () {
    String row(int n, int marker) => [
      n.toRadixString(16).toUpperCase().padLeft(2, '0'),
      for (var c = 0; c < 16; c++) '000000',
      // A byte, extended to 16 bits with its sign.
      (marker >= 0x80 ? 0xFF00 | marker : marker)
          .toRadixString(16)
          .toUpperCase()
          .padLeft(4, '0'),
      '0000',
      '0000',
    ].join(',');
    final text = [
      for (var i = 0; i < 100; i++)
        row(i, switch (i) {
          10 => 'f'.codeUnitAt(0),
          50 => 200,
          _ => 0,
        }),
    ].join('\n');
    final f = CytonSdFile.parse(text.codeUnits);
    expect(f.hasAccel, isFalse);
    expect(f.rate, 250); // assumed
    expect(f.markers.map((m) => m.value), ['f'.codeUnitAt(0), 200]);
    expect(f.markers.first.time, closeTo(10 / 250, 1e-12));
    expect(f.accel.every((v) => v == 0), isTrue);
    // Told otherwise: the accelerometer.
    final g = CytonSdFile.parse(text.codeUnits, mode: CytonBoardMode.defaults);
    expect(g.markers, isEmpty);
    expect(g.hasAccel, isTrue);
  });

  test('looksLike', () {
    expect(CytonSdFile.looksLike(bytes), isTrue);
    expect(CytonSdFile.looksLike('time,a,b\n1,2,3\n'.codeUnits), isFalse);
    expect(CytonSdFile.looksLike(''.codeUnits), isFalse);
  });

  test('read in pieces: the same, and done at the unused space', () {
    final whole = CytonSdFile.parse(bytes);
    final reader = CytonSdReader();
    final rows = <CytonSdRow>[];
    for (var a = 0; a < bytes.length && !reader.done; a += 1000) {
      rows.addAll(
        reader.add(bytes.sublist(a, (a + 1000).clamp(0, bytes.length))),
      );
    }
    rows.addAll(reader.close());
    expect(reader.done, isTrue);
    expect(rows, hasLength(whole.length));
    expect(rows.last.eeg, whole.eeg.sublist(299 * 16));
    expect(reader.skipped, 1);
    expect(reader.metadata, whole.metadata);
  });

  test('as XDF', () async {
    final f = CytonSdFile.parse(bytes);
    final out = BytesBuilder();
    // In pieces, as a file is read.
    final summary = await convertCytonSdToXdf(
      Stream.fromIterable([
        for (var a = 0; a < bytes.length; a += 4096)
          bytes.sublist(a, (a + 4096).clamp(0, bytes.length)),
      ]),
      _Collect(out),
      labels: ['Fp1'],
      types: ['EEG', 'EMG'],
      layoutLines: 100,
    );
    expect(summary.samples, 300);
    expect(summary.layout.rate, 250);
    expect(summary.layout.hasAccel, isTrue);
    expect(summary.skipped, 1);
    final x = loadXdf(
      out.takeBytes(),
      options: const XdfSyncOptions(dejitterTimestamps: false),
    );
    expect(x.streams, hasLength(2));
    final eeg = x.streams.firstWhere((s) => s.info.type == 'EEG');
    expect(eeg.info.channelCount, 16);
    expect(eeg.info.nominalRate, 250);
    expect(eeg.info.label(0), 'Fp1');
    expect(eeg.info.label(1), 'ch2');
    expect(eeg.timestamps, hasLength(300));
    expect(eeg.timestamps[1], closeTo(1 / 250, 1e-9));
    expect(eeg.channels[1][0], closeTo(f.eeg[1], 0.01));
    final accel = x.streams.firstWhere((s) => s.info.type == 'Accelerometer');
    expect(accel.channels[1][0], closeTo(f.accel[1], 1e-6));
    // The reading holds.
    expect(accel.channels[1][5], closeTo(f.accel[1], 1e-6));
  });

  test('markers as XDF', () async {
    String row(int n, int marker) => [
      n.toRadixString(16).padLeft(2, '0'),
      for (var c = 0; c < 8; c++) '000000',
      (marker >= 0x80 ? 0xFF00 | marker : marker)
          .toRadixString(16)
          .padLeft(4, '0'),
      '0000',
      '0000',
    ].join(',');
    final text = [for (var i = 0; i < 50; i++) row(i, i == 20 ? 150 : 0)];
    final out = BytesBuilder();
    final summary = await convertCytonSdToXdf(
      Stream.value('${text.join('\n')}\n'.codeUnits),
      _Collect(out),
    );
    expect(summary.markers, 1);
    final x = loadXdf(
      out.takeBytes(),
      options: const XdfSyncOptions(dejitterTimestamps: false),
    );
    final m = x.streams.firstWhere((s) => s.info.type == 'Markers');
    expect(m.strings.single, ['150']);
    expect(m.timestamps.single, closeTo(20 / 250, 1e-9));
    expect(x.streams.where((s) => s.info.type == 'Accelerometer'), isEmpty);
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
