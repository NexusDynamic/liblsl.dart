import 'dart:typed_data';

import 'package:lsl_tools/src/bridge/protocol.dart';
import 'package:lsl_tools/src/lsl_types.dart';
import 'package:test/test.dart';

void main() {
  final times = Float64List.fromList([1.5, 2.5]);

  (int, LslChunk) roundTrip(LslChunk c, int channels, LslFormat format) =>
      decodeSamples(encodeSamples(7, c, channels, format));

  test('float32 values travel as float32', () {
    final (id, c) = roundTrip(
      LslChunk(times, values: Float32List.fromList([0.25, -1, 3, 4])),
      2,
      LslFormat.float32,
    );
    expect(id, 7);
    expect(c.times, times);
    expect(c.values, isA<Float32List>());
    expect(c.values, [0.25, -1, 3, 4]);
  });

  test('double64 values keep their precision', () {
    const v = [1 / 3, 1e-300, -123456789.123456789, double.maxFinite];
    final (_, c) = roundTrip(
      LslChunk(times, typed: Float64List.fromList(v)),
      2,
      LslFormat.double64,
    );
    expect(c.values, isA<Float64List>());
    expect(c.values, v);
    expect(c.typed, v);
  });

  for (final (format, v, list) in [
    (LslFormat.int8, [-128, 127, 0, -1], isA<Int8List>()),
    (LslFormat.int16, [-32768, 32767, 1, -2], isA<Int16List>()),
    (LslFormat.int32, [-2147483648, 2147483647, 5, -6], isA<Int32List>()),
    // Above 2^53: exact only as ints, not as doubles.
    (
      LslFormat.int64,
      [-9223372036854775808, 9223372036854775807, (1 << 60) + 1, -7],
      isA<Int64List>(),
    ),
  ]) {
    test('${format.name} values are exact', () {
      final (_, c) = roundTrip(
        LslChunk(times, typed: Int64List.fromList(v)),
        2,
        format,
      );
      expect(c.typed, list);
      expect(c.typed, v);
      expect(c.values, [for (final x in v) x.toDouble()]);
    });
  }

  test('doubles sent as integers are rounded', () {
    final (_, c) = roundTrip(
      LslChunk(
        times,
        values: Float64List.fromList([1.4, 1.6, double.nan, -2.5]),
      ),
      2,
      LslFormat.int32,
    );
    expect(c.typed, [1, 2, 0, -3]);
  });

  test('every channel of a string stream travels', () {
    const s = ['a', 'b', 'ç', '', 'e', 'f'];
    final (_, c) = roundTrip(LslChunk(times, strings: s), 3, LslFormat.string);
    expect(c.strings, s);
    expect(c.values, isNull);
  });

  test('an unknown value kind is refused', () {
    final bytes = encodeSamples(1, LslChunk(times, values: Float32List(2)), 1);
    bytes[12] = 99;
    expect(() => decodeSamples(bytes), throwsFormatException);
  });
}
