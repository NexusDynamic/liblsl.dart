import 'dart:convert';
import 'dart:typed_data';

import 'package:lsl_core/lsl_core.dart';

/// The four bytes every XDF file starts with.
const xdfMagic = [0x58, 0x44, 0x46, 0x3A]; // "XDF:"

/// Kinds of XDF chunks.
enum XdfTag {
  fileHeader(1),
  streamHeader(2),
  samples(3),
  clockOffset(4),
  boundary(5),
  streamFooter(6);

  final int value;
  const XdfTag(this.value);

  static XdfTag? of(int value) {
    for (final t in values) {
      if (t.value == value) return t;
    }
    return null;
  }
}

/// How the values of a stream are stored: the LSL channel format.
@Deprecated('Use LSLChannelFormat (package:lsl_core)')
typedef XdfFormat = LSLChannelFormat;

/// The boundary chunk's content: a fixed UUID that lets a reader find the
/// next chunk in a damaged file.
const xdfBoundaryUuid = [
  0x43, 0xA5, 0x46, 0xDC, 0xCB, 0xF5, 0x41, 0x0F, //
  0xB3, 0x0E, 0xD5, 0x46, 0x73, 0x83, 0xCB, 0xE4,
];

/// Reads little-endian values from [bytes], from [position] on.
class XdfReader {
  final Uint8List bytes;
  final ByteData _data;
  int position;

  XdfReader(this.bytes, [this.position = 0])
    : _data = ByteData.sublistView(bytes);

  int get remaining => bytes.length - position;

  bool get atEnd => position >= bytes.length;

  void _need(int n) {
    if (position + n > bytes.length) {
      throw const FormatException('Unexpected end of XDF data');
    }
  }

  int uint8() {
    _need(1);
    return bytes[position++];
  }

  int uint16() {
    _need(2);
    final v = _data.getUint16(position, Endian.little);
    position += 2;
    return v;
  }

  int uint32() {
    _need(4);
    final v = _data.getUint32(position, Endian.little);
    position += 4;
    return v;
  }

  int uint64() {
    _need(8);
    // Lengths only; the web has no 64-bit getter, so combine two halves.
    final lo = _data.getUint32(position, Endian.little);
    final hi = _data.getUint32(position + 4, Endian.little);
    position += 8;
    return hi * 0x100000000 + lo;
  }

  double float64() {
    _need(8);
    final v = _data.getFloat64(position, Endian.little);
    position += 8;
    return v;
  }

  /// A variable-length integer: a byte giving its size (1, 4 or 8), then
  /// the value.
  int varLen() => switch (uint8()) {
    1 => uint8(),
    4 => uint32(),
    8 => uint64(),
    final n => throw FormatException('Invalid length size $n'),
  };

  Uint8List take(int n) {
    _need(n);
    final v = Uint8List.sublistView(bytes, position, position + n);
    position += n;
    return v;
  }

  String utf8String(int n) => utf8.decode(take(n), allowMalformed: true);

  /// Read [count] values of [format] into [out] from [offset]: as doubles
  /// for a `List<double>` (integers exact up to 2^53), exactly for a typed
  /// list of the format. [onInexact] is called if an int64 value could not
  /// be held exactly.
  void values(
    LSLChannelFormat format,
    int count,
    List<num> out,
    int offset, {
    void Function()? onInexact,
  }) {
    if (format.isString) throw ArgumentError('Strings are not numeric values');
    _need(count * format.byteWidth);
    readValuesInto(
      _data,
      position,
      format,
      count,
      out,
      outOffset: offset,
      onInexact: onInexact,
    );
    position += count * format.byteWidth;
  }

  /// Skip [count] values of [format].
  void skipValues(LSLChannelFormat format, int count) {
    if (format.isString) {
      for (var i = 0; i < count; i++) {
        final n = varLen();
        _need(n);
        position += n;
      }
    } else {
      _need(count * format.byteWidth);
      position += count * format.byteWidth;
    }
  }
}

/// Writes little-endian values.
class XdfBytesWriter {
  final _b = BytesBuilder(copy: false);
  final _scratch = ByteData(8);

  int get length => _b.length;

  Uint8List takeBytes() => _b.takeBytes();

  void bytes(List<int> v) => _b.add(v);

  void uint8(int v) => _b.addByte(v);

  void _put(int n) =>
      _b.add(Uint8List.fromList(_scratch.buffer.asUint8List(0, n)));

  void uint16(int v) {
    _scratch.setUint16(0, v, Endian.little);
    _put(2);
  }

  void uint32(int v) {
    _scratch.setUint32(0, v, Endian.little);
    _put(4);
  }

  void uint64(int v) {
    _scratch.setUint32(0, v % 0x100000000, Endian.little);
    _scratch.setUint32(4, v ~/ 0x100000000, Endian.little);
    _put(8);
  }

  void float64(double v) {
    _scratch.setFloat64(0, v, Endian.little);
    _put(8);
  }

  /// A variable-length integer in the fewest bytes (1, 4 or 8).
  void varLen(int v) {
    if (v < 0x100) {
      uint8(1);
      uint8(v);
    } else if (v < 0x100000000) {
      uint8(4);
      uint32(v);
    } else {
      uint8(8);
      uint64(v);
    }
  }

  /// [values] as [format] (rounded for integer formats).
  void values(LSLChannelFormat format, List<num> values) {
    if (format.isString) throw ArgumentError('Strings are not numeric values');
    final out = ByteData(values.length * format.byteWidth);
    writeValues(out, 0, format, values, values.length);
    _b.add(out.buffer.asUint8List());
  }

  void string(String s) {
    final b = utf8.encode(s);
    varLen(b.length);
    _b.add(b);
  }
}
