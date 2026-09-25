import 'dart:convert';
import 'dart:typed_data';

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

/// How the values of a stream are stored.
enum XdfFormat {
  float32('float32', 4),
  double64('double64', 8),
  string('string', 0),
  int32('int32', 4),
  int16('int16', 2),
  int8('int8', 1),
  int64('int64', 8);

  /// The name in stream headers (`channel_format`).
  final String name;

  /// Bytes per value; 0 for strings.
  final int size;

  const XdfFormat(this.name, this.size);

  bool get isString => this == string;

  static XdfFormat parse(String name) {
    final n = name.trim().toLowerCase();
    for (final f in values) {
      if (f.name == n) return f;
    }
    // Some writers use "double" or "float".
    if (n == 'double') return double64;
    if (n == 'float') return float32;
    throw FormatException('Unknown channel format "$name"');
  }
}

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

  /// Read [count] values of [format] into [out] from [offset], as doubles.
  void values(XdfFormat format, int count, List<double> out, int offset) {
    _need(count * format.size);
    var p = position;
    final d = _data;
    switch (format) {
      case XdfFormat.float32:
        for (var i = 0; i < count; i++, p += 4) {
          out[offset + i] = d.getFloat32(p, Endian.little);
        }
      case XdfFormat.double64:
        for (var i = 0; i < count; i++, p += 8) {
          out[offset + i] = d.getFloat64(p, Endian.little);
        }
      case XdfFormat.int32:
        for (var i = 0; i < count; i++, p += 4) {
          out[offset + i] = d.getInt32(p, Endian.little).toDouble();
        }
      case XdfFormat.int16:
        for (var i = 0; i < count; i++, p += 2) {
          out[offset + i] = d.getInt16(p, Endian.little).toDouble();
        }
      case XdfFormat.int8:
        for (var i = 0; i < count; i++, p += 1) {
          out[offset + i] = d.getInt8(p).toDouble();
        }
      case XdfFormat.int64:
        for (var i = 0; i < count; i++, p += 8) {
          // Two halves (no 64-bit getter on the web); exact up to 2^53.
          final lo = d.getUint32(p, Endian.little);
          final hi = d.getInt32(p + 4, Endian.little);
          out[offset + i] = hi * 4294967296.0 + lo;
        }
      case XdfFormat.string:
        throw ArgumentError('Strings are not numeric values');
    }
    position = p;
  }

  /// Skip [count] values of [format].
  void skipValues(XdfFormat format, int count) {
    if (format.isString) {
      for (var i = 0; i < count; i++) {
        final n = varLen();
        _need(n);
        position += n;
      }
    } else {
      _need(count * format.size);
      position += count * format.size;
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

  /// [values] as [format].
  void values(XdfFormat format, List<double> values) {
    final n = values.length;
    final out = ByteData(n * format.size);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      switch (format) {
        case XdfFormat.float32:
          out.setFloat32(i * 4, v, Endian.little);
        case XdfFormat.double64:
          out.setFloat64(i * 8, v, Endian.little);
        case XdfFormat.int32:
          out.setInt32(i * 4, v.round(), Endian.little);
        case XdfFormat.int16:
          out.setInt16(i * 2, v.round(), Endian.little);
        case XdfFormat.int8:
          out.setInt8(i, v.round());
        case XdfFormat.int64:
          final r = v.round();
          out.setUint32(i * 8, r & 0xFFFFFFFF, Endian.little);
          out.setInt32(
            i * 8 + 4,
            (r - (r & 0xFFFFFFFF)) ~/ 4294967296,
            Endian.little,
          );
        case XdfFormat.string:
          throw ArgumentError('Strings are not numeric values');
      }
    }
    _b.add(out.buffer.asUint8List());
  }

  void string(String s) {
    final b = utf8.encode(s);
    varLen(b.length);
    _b.add(b);
  }
}
