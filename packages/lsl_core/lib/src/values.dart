import 'dart:typed_data';

import 'format.dart';

/// Whether ints hold 64 bits here. Where they are JavaScript numbers
/// (dart2js) there is no `Int64List` or 64-bit [ByteData] access, and only
/// integers up to ±2^53 are exact; int64 values are then kept as doubles.
const bool exactInt64 = !identical(0, 0.0);

const _twoTo32 = 4294967296;
const _twoTo53 = 9007199254740992;

/// A typed list for [n] values of [format]. int64 is an [Int64List], or a
/// [Float64List] where not [exactInt64]. Not for [LSLChannelFormat.string].
TypedData typedListFor(LSLChannelFormat format, int n) =>
    switch (format.outletFormat) {
      LSLChannelFormat.double64 => Float64List(n),
      LSLChannelFormat.int8 => Int8List(n),
      LSLChannelFormat.int16 => Int16List(n),
      LSLChannelFormat.int32 => Int32List(n),
      LSLChannelFormat.int64 => exactInt64 ? Int64List(n) : Float64List(n),
      LSLChannelFormat.string => throw ArgumentError(
        'No typed list for strings',
      ),
      _ => Float32List(n),
    };

/// The format whose values [data] holds, or null for other typed data.
LSLChannelFormat? formatOf(TypedData data) => switch (data) {
  Float32List() => LSLChannelFormat.float32,
  Float64List() => LSLChannelFormat.double64,
  Int8List() => LSLChannelFormat.int8,
  Int16List() => LSLChannelFormat.int16,
  Int32List() => LSLChannelFormat.int32,
  Int64List() => LSLChannelFormat.int64,
  _ => null,
};

/// [v] as an integer: rounded, and 0 if not finite.
int valueToInt(num v) => v is int ? v : (v.isFinite ? v.round() : 0);

/// [data] (any numeric typed list) as the typed list for [format]: itself
/// if it is one already, else converted (rounded for integer formats).
TypedData asFormat(LSLChannelFormat format, TypedData data) {
  final f = format.outletFormat;
  if (formatOf(data) == f) return data;
  final v = data as List<num>;
  return switch (f) {
    LSLChannelFormat.double64 => Float64List.fromList([
      for (final x in v) x.toDouble(),
    ]),
    LSLChannelFormat.int8 => Int8List.fromList([
      for (final x in v) valueToInt(x),
    ]),
    LSLChannelFormat.int16 => Int16List.fromList([
      for (final x in v) valueToInt(x),
    ]),
    LSLChannelFormat.int32 => Int32List.fromList([
      for (final x in v) valueToInt(x),
    ]),
    LSLChannelFormat.int64 =>
      exactInt64
          ? Int64List.fromList([for (final x in v) valueToInt(x)])
          : (data is Float64List
                ? data
                : Float64List.fromList([
                    for (final x in v) valueToInt(x).toDouble(),
                  ])),
    _ => Float32List.fromList([for (final x in v) x.toDouble()]),
  };
}

/// [data] as doubles: a [Float32List] or [Float64List] as it is, other
/// typed data copied to a [Float64List] (integers exact up to 2^53).
List<double> asDoubles(TypedData data) {
  if (data is Float32List) return data;
  if (data is Float64List) return data;
  final v = data as List<num>;
  final out = Float64List(v.length);
  for (var i = 0; i < out.length; i++) {
    out[i] = v[i].toDouble();
  }
  return out;
}

/// Write [count] values of [src] (from [from]) at [offset] of [d] as
/// little-endian [format]. Returns the bytes written.
int writeValues(
  ByteData d,
  int offset,
  LSLChannelFormat format,
  List<num> src,
  int count, {
  int from = 0,
}) {
  var p = offset;
  final end = from + count;
  switch (format.outletFormat) {
    case LSLChannelFormat.double64:
      for (var i = from; i < end; i++, p += 8) {
        d.setFloat64(p, src[i].toDouble(), Endian.little);
      }
    case LSLChannelFormat.int8:
      for (var i = from; i < end; i++, p++) {
        d.setInt8(p, valueToInt(src[i]));
      }
    case LSLChannelFormat.int16:
      for (var i = from; i < end; i++, p += 2) {
        d.setInt16(p, valueToInt(src[i]), Endian.little);
      }
    case LSLChannelFormat.int32:
      for (var i = from; i < end; i++, p += 4) {
        d.setInt32(p, valueToInt(src[i]), Endian.little);
      }
    case LSLChannelFormat.int64:
      for (var i = from; i < end; i++, p += 8) {
        _setInt64(d, p, valueToInt(src[i]));
      }
    case LSLChannelFormat.string:
      throw ArgumentError('Strings have no fixed-width encoding');
    default:
      for (var i = from; i < end; i++, p += 4) {
        d.setFloat32(p, src[i].toDouble(), Endian.little);
      }
  }
  return p - offset;
}

/// [count] little-endian values of [format] at [offset] of [d], in the
/// typed list [typedListFor] gives. [onInexact] is called once if an int64
/// value could not be held exactly (beyond ±2^53 where not [exactInt64]).
TypedData readValues(
  ByteData d,
  int offset,
  LSLChannelFormat format,
  int count, {
  void Function()? onInexact,
}) {
  final out = typedListFor(format, count);
  readValuesInto(
    d,
    offset,
    format,
    count,
    out as List<num>,
    onInexact: onInexact,
  );
  return out;
}

/// As [readValues], into [out] from [outOffset]: any list of numbers (a
/// `List<double>` takes integers as doubles, exact up to 2^53).
void readValuesInto(
  ByteData d,
  int offset,
  LSLChannelFormat format,
  int count,
  List<num> out, {
  int outOffset = 0,
  void Function()? onInexact,
}) {
  var p = offset;
  final end = outOffset + count;
  final doubles = out is List<double>;
  void put(int i, int v) => doubles ? out[i] = v.toDouble() : out[i] = v;
  switch (format.outletFormat) {
    case LSLChannelFormat.double64:
      for (var i = outOffset; i < end; i++, p += 8) {
        out[i] = d.getFloat64(p, Endian.little);
      }
    case LSLChannelFormat.int8:
      for (var i = outOffset; i < end; i++, p++) {
        put(i, d.getInt8(p));
      }
    case LSLChannelFormat.int16:
      for (var i = outOffset; i < end; i++, p += 2) {
        put(i, d.getInt16(p, Endian.little));
      }
    case LSLChannelFormat.int32:
      for (var i = outOffset; i < end; i++, p += 4) {
        put(i, d.getInt32(p, Endian.little));
      }
    case LSLChannelFormat.int64:
      var inexact = false;
      for (var i = outOffset; i < end; i++, p += 8) {
        if (exactInt64) {
          final v = d.getInt64(p, Endian.little);
          if (doubles && (v > _twoTo53 || v < -_twoTo53)) inexact = true;
          put(i, v);
        } else {
          final hi = d.getInt32(p + 4, Endian.little);
          // Beyond ±2^53 when the high word needs more than 21 bits.
          if (hi >= 0x200000 || hi < -0x200000) inexact = true;
          out[i] = hi * _twoTo32 + d.getUint32(p, Endian.little);
        }
      }
      if (inexact) onInexact?.call();
    case LSLChannelFormat.string:
      throw ArgumentError('Strings have no fixed-width encoding');
    default:
      for (var i = outOffset; i < end; i++, p += 4) {
        out[i] = d.getFloat32(p, Endian.little);
      }
  }
}

void _setInt64(ByteData d, int p, int v) {
  if (exactInt64) return d.setInt64(p, v, Endian.little);
  final hi = (v / _twoTo32).floor();
  d.setUint32(p, v - hi * _twoTo32, Endian.little);
  d.setInt32(p + 4, hi, Endian.little);
}

/// Values [a] to [z] of [data], a view of the same typed list type.
TypedData sliceTyped(TypedData data, int a, int z) => switch (data) {
  Float32List() => Float32List.sublistView(data, a, z),
  Float64List() => Float64List.sublistView(data, a, z),
  Int8List() => Int8List.sublistView(data, a, z),
  Int16List() => Int16List.sublistView(data, a, z),
  Int32List() => Int32List.sublistView(data, a, z),
  Int64List() => Int64List.sublistView(data, a, z),
  _ => throw ArgumentError('Not sample values: ${data.runtimeType}'),
};
