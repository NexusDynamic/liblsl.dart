import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xdf/xdf.dart';
import 'package:xml/xml.dart';

/// Collects written bytes.
class _Bytes implements Sink<List<int>> {
  final builder = BytesBuilder();
  @override
  void add(List<int> data) => builder.add(data);
  @override
  void close() {}
}

void main() {
  test('written files read back as written', () async {
    final out = _Bytes();
    final w = XdfWriter(out, header: {'datetime': '2026-09-24T12:00:00'});
    for (final (id, format) in [
      (1, XdfFormat.float32),
      (2, XdfFormat.int16),
      (3, XdfFormat.double64),
      (4, XdfFormat.int64),
      (5, XdfFormat.int8),
      (6, XdfFormat.int32),
    ]) {
      w.addStream(
        id,
        XdfStreamInfo(
          name: 'S$id',
          type: 'EEG',
          channelCount: 2,
          nominalRate: 100,
          format: format,
          channels: const [
            XdfChannel(label: 'Cz', unit: 'microvolts', type: 'EEG'),
            XdfChannel(label: 'Pz'),
          ],
        ),
      );
    }
    w.addStream(
      9,
      XdfStreamInfo(
        name: 'Markers',
        type: 'Markers',
        channelCount: 1,
        format: XdfFormat.string,
      ),
    );
    for (var block = 0; block < 5; block++) {
      final ts = [
        for (var i = 0; i < 10; i++)
          // Every other time stamp left out: 1 / nominal rate after the last.
          i.isOdd ? double.nan : 100 + (block * 10 + i) / 100,
      ];
      final values = [
        for (var i = 0; i < 10; i++) ...[
          (block * 10 + i).toDouble(),
          -(block * 10 + i).toDouble(),
        ],
      ];
      for (var id = 1; id <= 6; id++) {
        w.writeSamples(id, ts, values);
      }
      w.writeStrings(9, [100 + block * 0.1], ['block ${block + 1} ü']);
      w.writeClockOffset(1, 100 + block * 0.1, 0.25);
      w.writeBoundary();
    }
    await w.close();

    final rec = loadXdf(out.builder.takeBytes(), options: XdfSyncOptions.raw);
    expect(
      rec.header!.getElement('datetime')!.innerText,
      '2026-09-24T12:00:00',
    );
    expect(rec.streams, hasLength(7));
    for (var id = 1; id <= 6; id++) {
      final s = rec.streams.firstWhere((s) => s.id == id);
      expect(s.length, 50);
      expect(s.info.label(0), 'Cz');
      expect(s.info.unit(0), 'microvolts');
      expect(s.info.label(1), 'Pz');
      expect(s.footer!.sampleCount, 50);
      for (var i = 0; i < 50; i++) {
        expect(s.timestamps[i], closeTo(100 + i / 100, 1e-9));
        expect(s.channels[0][i], i);
        expect(s.channels[1][i], -i);
      }
    }
    final m = rec.stream('Markers')!;
    expect(m.strings.map((s) => s.single), [
      for (var b = 1; b <= 5; b++) 'block $b ü',
    ]);
    expect(rec.stream('S1')!.clockTimes, hasLength(5));
  });

  test('clock offsets shift time stamps onto the recorder clock', () async {
    final out = _Bytes();
    final w = XdfWriter(out);
    w.addStream(
      1,
      XdfStreamInfo(name: 'EEG', channelCount: 1, nominalRate: 250),
    );
    final rng = math.Random(1);
    const n = 2500;
    final ts = [
      for (var i = 0; i < n; i++)
        50 + i / 250 + (rng.nextDouble() - 0.5) / 1000,
    ];
    w.writeSamples(1, ts, [for (var i = 0; i < n; i++) i.toDouble()]);
    for (var k = 0; k < 10; k++) {
      w.writeClockOffset(1, 50.0 + k, 3.5);
    }
    await w.close();
    final rec = loadXdf(out.builder.takeBytes());
    final s = rec.streams.single;
    // Dejittered: a straight line, offset by 3.5 s.
    expect(s.timestamps.first, closeTo(53.5, 1e-3));
    expect(s.timestamps[n - 1] - s.timestamps[n - 2], closeTo(1 / 250, 1e-6));
    expect(s.effectiveRate, closeTo(250, 0.01));
  });
}
