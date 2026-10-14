import 'dart:typed_data';

import 'package:lsl_core/lsl_core.dart';
import 'package:test/test.dart';

void main() {
  group('LSLChannelFormat', () {
    test('parses LSL names and the aliases some writers use', () {
      for (final f in LSLChannelFormat.values) {
        expect(LSLChannelFormat.parse(f.name), f);
      }
      expect(LSLChannelFormat.parse(' Double '), LSLChannelFormat.double64);
      expect(LSLChannelFormat.parse('float'), LSLChannelFormat.float32);
      expect(() => LSLChannelFormat.parse('int128'), throwsFormatException);
    });

    test('widths, and undefined outlets are float32', () {
      expect(LSLChannelFormat.int16.byteWidth, 2);
      expect(LSLChannelFormat.int64.byteWidth, 8);
      expect(LSLChannelFormat.string.byteWidth, 0);
      expect(LSLChannelFormat.undefined.outletFormat, LSLChannelFormat.float32);
      expect(LSLChannelFormat.int8.isInteger, isTrue);
      expect(LSLChannelFormat.double64.isInteger, isFalse);
    });
  });

  group('values', () {
    final cases = <LSLChannelFormat, List<num>>{
      LSLChannelFormat.float32: [0.25, -1.5, 3, 1024.5],
      LSLChannelFormat.double64: [1 / 3, -1e-300, double.maxFinite, 0],
      LSLChannelFormat.int8: [-128, 127, 0, -1],
      LSLChannelFormat.int16: [-32768, 32767, 1, -2],
      LSLChannelFormat.int32: [-2147483648, 2147483647, 5, -6],
      // Beyond 2^53: exact only as ints.
      LSLChannelFormat.int64: [
        -9223372036854775808,
        9223372036854775807,
        (1 << 60) + 1,
        -7,
      ],
    };
    for (final MapEntry(key: f, value: v) in cases.entries) {
      test('${f.name} round-trips exactly', () {
        final d = ByteData(v.length * f.byteWidth + 3);
        expect(writeValues(d, 3, f, v, v.length), v.length * f.byteWidth);
        final back = readValues(d, 3, f, v.length);
        expect(formatOf(back), f);
        expect(back, v);
      });
    }

    test('an int64 read as doubles reports what it rounded', () {
      final d = ByteData(16)
        ..setInt64(0, (1 << 60) + 1, Endian.little)
        ..setInt64(8, 5, Endian.little);
      var inexact = 0;
      final out = Float64List(2);
      readValuesInto(
        d,
        0,
        LSLChannelFormat.int64,
        2,
        out,
        onInexact: () => inexact++,
      );
      expect(inexact, 1);
      expect(out[1], 5);
    });

    test('conversion rounds to integers and keeps matching lists', () {
      final f = Float64List.fromList([1.4, 1.6, double.nan, -2.5]);
      expect(asFormat(LSLChannelFormat.int32, f), [1, 2, 0, -3]);
      expect(identical(asFormat(LSLChannelFormat.double64, f), f), isTrue);
      expect(asFormat(LSLChannelFormat.undefined, f), isA<Float32List>());
      expect(asDoubles(Int16List.fromList([3, -4])), [3.0, -4.0]);
      expect(
        sliceTyped(Int64List.fromList([1, 2, 3, 4]), 1, 3),
        allOf(isA<Int64List>(), [2, 3]),
      );
    });
  });

  group('polling', () {
    test('poll intervals follow the rate within what the wait manages', () {
      expect(pollIntervalFor(250), const Duration(milliseconds: 4));
      expect(pollIntervalFor(5000), const Duration(milliseconds: 1));
      expect(
        pollIntervalFor(5000, busyWait: true),
        const Duration(microseconds: 200),
      );
      expect(pollIntervalFor(10), const Duration(milliseconds: 10));
      expect(pollIntervalFor(0), const Duration(milliseconds: 10));
      expect(pullCapacity(500, const Duration(seconds: 2), min: 256), 1000);
      expect(pullCapacity(0, const Duration(seconds: 2), min: 256), 256);
    });

    test('a drain pulls until a pull comes back short', () async {
      final inlet = _Inlet([300, 300, 10, 999]);
      final got = <int>[];
      expect(await drainInlet(inlet, 300, (c) => got.add(c.length)), 610);
      expect(got, [300, 300, 10]);
      expect(await drainInlet(inlet, 300, (_) {}, stop: () => true), 0);
    });
  });

  group('info XML', () {
    test('built and read back, with channels and desc groups', () {
      final xml = buildInfoXml(
        name: 'EEG <1>',
        type: 'EEG',
        channelCount: 2,
        rate: 250,
        format: LSLChannelFormat.int16,
        channels: const [
          LSLChannel('Cz', unit: 'microvolts'),
          LSLChannel('Pz'),
        ],
        desc: {
          'acquisition': {'by': 'test', 'empty': ''},
        },
      );
      final info = infoElement(xml);
      expect(xmlField(info, 'name'), 'EEG <1>');
      expect(infoField(xml, 'channel_format'), 'int16');
      expect(channelsOf(info), const [
        LSLChannel('Cz', unit: 'microvolts'),
        LSLChannel('Pz'),
      ]);
      expect(
        xmlField(info.getElement('desc')?.getElement('acquisition'), 'by'),
        'test',
      );
      expect(infoField('not xml', 'name'), '');
    });
  });
}

/// An inlet that hands out chunks of the given sizes.
class _Inlet implements LslInlet {
  final List<int> sizes;
  _Inlet(this.sizes);

  @override
  Future<LslChunk> pull(int maxSamples) async {
    if (sizes.isEmpty) return LslChunk.empty;
    final n = sizes.removeAt(0);
    return LslChunk(Float64List(n));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
