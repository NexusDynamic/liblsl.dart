@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xdf/xdf.dart';

/// What pyxdf makes of the example files (tool/pyxdf_reference.py).
final _reference =
    jsonDecode(File('test/fixtures/pyxdf_reference.json').readAsStringSync())
        as Map<String, Object?>;

List<double> _doubles(Object? o) => [
  for (final v in o! as List) (v as num).toDouble(),
];

void main() {
  for (final file in ['minimal', 'clock_resets', 'empty_streams']) {
    for (final mode in ['default', 'raw']) {
      test('$file.xdf ($mode) matches pyxdf', () {
        final rec = loadXdf(
          File('test/fixtures/$file.xdf').readAsBytesSync(),
          options: mode == 'raw' ? XdfSyncOptions.raw : const XdfSyncOptions(),
        );
        final expected =
            ((_reference[file]! as Map<String, Object?>)[mode]!
                    as List<Object?>)
                .cast<Map<String, Object?>>();
        expect(rec.streams, hasLength(expected.length));
        for (final e in expected) {
          final s = rec.streams.firstWhere((s) => s.id == e['id']);
          final what = '${e['name']}';
          expect(s.info.name, e['name']);
          expect(s.length, e['n'], reason: what);
          expect(
            s.effectiveRate,
            closeTo((e['effective_srate']! as num).toDouble(), 1e-6),
            reason: what,
          );
          expect(
            [
              for (final (a, b) in s.segments) [a, b],
            ],
            e['segments'],
            reason: '$what segments',
          );
          if (mode == 'default') {
            expect(
              [
                for (final (a, b) in s.clockSegments) [a, b],
              ],
              e['clock_segments'],
              reason: '$what clock segments',
            );
          }
          final n = s.length;
          if (n == 0) continue;
          final step = n ~/ 50 > 0 ? n ~/ 50 : 1;
          final every = _doubles(e['ts_every']);
          for (var k = 0; k < every.length; k++) {
            expect(
              s.timestamps[k * step],
              closeTo(every[k], 1e-6),
              reason: '$what time stamp ${k * step}',
            );
          }
          if (e.containsKey('val_head')) {
            final head = (e['val_head']! as List<Object?>)
                .cast<List<Object?>>();
            for (var i = 0; i < head.length; i++) {
              expect(
                [for (final c in s.channels) c[i]],
                _doubles(head[i]),
                reason: '$what sample $i',
              );
            }
            final tail = (e['val_tail']! as List<Object?>)
                .cast<List<Object?>>();
            for (var i = 0; i < tail.length; i++) {
              final row = n - tail.length + i;
              expect(
                [for (final c in s.channels) c[row]],
                _doubles(tail[i]),
                reason: '$what sample $row',
              );
            }
          }
          if (e.containsKey('str_head')) {
            expect(s.strings.take(3), e['str_head'], reason: what);
            expect(
              s.strings.skip(n > 3 ? n - 3 : 0),
              e['str_tail'],
              reason: what,
            );
          }
        }
      });
    }
  }

  test('stream headers are parsed', () {
    final rec = loadXdf(File('test/fixtures/minimal.xdf').readAsBytesSync());
    final eeg = rec.stream('SendDataC')!;
    expect(eeg.info.type, 'EEG');
    expect(eeg.info.channelCount, 3);
    expect(eeg.info.nominalRate, 10);
    expect(eeg.info.format, XdfFormat.int16);
    expect(eeg.footer!.sampleCount, 9);
    expect(eeg.footer!.clockOffsets, hasLength(2));
    expect(eeg.info.label(0), 'ch1');
    final markers = rec.stream('SendDataString')!;
    expect(markers.info.format, XdfFormat.string);
  });
}
