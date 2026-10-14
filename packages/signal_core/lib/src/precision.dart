import 'dart:typed_data';

import 'pyramid.dart' show SummaryPyramid;
import 'requests.dart' show Envelope;

/// How sample values are kept in memory.
///
/// Recordings and streams are research data: by default every value is
/// kept as the source has it ([exact]). Keeping them as 32-bit floats
/// ([compact]) halves the memory they take and has to be asked for.
///
/// Summaries drawn on screen (an [Envelope]'s bins, the
/// [SummaryPyramid]) are 32-bit either way: they are pixels, not data.
enum SamplePrecision {
  /// 64-bit floats: every float32 and float64 value as it is, integers
  /// exact up to 2^53. The default.
  exact,

  /// 32-bit floats: half the memory, about 7 significant digits. Values
  /// with more lose them.
  compact;

  /// A list for [n] values, filled with [fill] if given.
  List<double> column(int n, [double? fill]) {
    final c = this == compact ? Float32List(n) : Float64List(n);
    if (fill != null) c.fillRange(0, n, fill);
    return c;
  }

  /// [values] in a list of this precision: a copy, or [values] itself if
  /// it is one already and [copy] is false.
  List<double> of(List<double> values, {bool copy = true}) {
    if (!copy &&
        (this == compact ? values is Float32List : values is Float64List)) {
      return values;
    }
    return this == compact
        ? Float32List.fromList(values)
        : Float64List.fromList(values);
  }

  /// The precision [values] is kept in.
  static SamplePrecision ofList(List<double> values) =>
      values is Float32List ? compact : exact;
}

/// Bytes [values] takes: its typed data size, or 8 per value.
int bytesOf(List<double> values) => values is TypedData
    ? (values as TypedData).lengthInBytes
    : values.length * 8;
