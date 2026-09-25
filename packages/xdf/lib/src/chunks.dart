import 'dart:typed_data';

import 'format.dart';

/// One chunk of an XDF file: its [tag] and [content] (after the tag), which
/// starts at [offset] in the file.
class XdfChunk {
  final int tag;
  final int offset;
  final Uint8List content;

  const XdfChunk(this.tag, this.offset, this.content);

  XdfTag? get kind => XdfTag.of(tag);

  /// The stream a stream header, samples, clock offset or footer chunk
  /// belongs to.
  int get streamId =>
      ByteData.sublistView(content, 0, 4).getUint32(0, Endian.little);
}

/// Whether [bytes] start like an XDF file.
bool isXdf(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == xdfMagic[0] &&
    bytes[1] == xdfMagic[1] &&
    bytes[2] == xdfMagic[2] &&
    bytes[3] == xdfMagic[3];

/// Where a chunk's header says its content is: [contentOffset] and
/// [contentLength] (after the tag), with the [tag].
typedef XdfChunkHeader = ({int tag, int contentOffset, int contentLength});

/// Parse the chunk header at [position] of [bytes], or null if [bytes] end
/// before it does (at most 11 bytes are needed).
XdfChunkHeader? readChunkHeader(Uint8List bytes, int position) {
  if (position >= bytes.length) return null;
  final r = XdfReader(bytes, position);
  try {
    final length = r.varLen();
    if (length < 2) throw FormatException('Invalid chunk length $length');
    final tag = r.uint16();
    return (tag: tag, contentOffset: r.position, contentLength: length - 2);
  } on FormatException catch (e) {
    if (e.message.startsWith('Unexpected end')) return null;
    rethrow;
  }
}

/// The chunks of a whole XDF file in memory. A truncated last chunk (a
/// recording that was cut off) is left out.
Iterable<XdfChunk> readChunks(Uint8List bytes) sync* {
  if (!isXdf(bytes)) throw const FormatException('Not an XDF file');
  var p = 4;
  while (p < bytes.length) {
    final h = readChunkHeader(bytes, p);
    if (h == null) return;
    final end = h.contentOffset + h.contentLength;
    if (end > bytes.length) return;
    yield XdfChunk(
      h.tag,
      h.contentOffset,
      Uint8List.sublistView(bytes, h.contentOffset, end),
    );
    p = end;
  }
}

/// The samples of one samples chunk.
class XdfSamples {
  final int streamId;

  /// Time stamps; NaN where the chunk leaves one out (it is then the
  /// previous one plus 1 / nominal rate).
  final Float64List timestamps;

  /// Numeric values, sample after sample (`[sample * channels + channel]`),
  /// or null for string streams.
  final Float64List? values;

  /// String values, sample after sample, or null for numeric streams.
  final List<String>? strings;

  const XdfSamples(this.streamId, this.timestamps, this.values, this.strings);

  int get length => timestamps.length;
}

/// Decode a samples chunk's [content] for a stream of [format] with
/// [channels] channels. With [values] false, numeric values are skipped
/// (time stamps only).
XdfSamples readSamples(
  Uint8List content,
  XdfFormat format,
  int channels, {
  bool values = true,
}) {
  final r = XdfReader(content);
  final id = r.uint32();
  final n = r.varLen();
  final ts = Float64List(n);
  final numeric = !format.isString && values ? Float64List(n * channels) : null;
  final strings = format.isString && values ? <String>[] : null;
  for (var i = 0; i < n; i++) {
    final tsBytes = r.uint8();
    ts[i] = switch (tsBytes) {
      8 => r.float64(),
      0 => double.nan,
      _ => throw FormatException('Invalid time stamp size $tsBytes'),
    };
    if (format.isString) {
      if (strings == null) {
        r.skipValues(format, channels);
      } else {
        for (var c = 0; c < channels; c++) {
          strings.add(r.utf8String(r.varLen()));
        }
      }
    } else if (numeric != null) {
      r.values(format, channels, numeric, i * channels);
    } else {
      r.skipValues(format, channels);
    }
  }
  return XdfSamples(id, ts, numeric, strings);
}

/// Fill the time stamps that [samples] leave out (NaN): the previous one
/// plus 1 / [nominalRate] (the previous chunk's last is [previous]).
/// Returns the last time stamp.
double fillTimestamps(Float64List ts, double previous, double nominalRate) {
  final step = nominalRate > 0 ? 1 / nominalRate : 0.0;
  var last = previous;
  for (var i = 0; i < ts.length; i++) {
    if (ts[i].isNaN) {
      ts[i] = last + step;
    }
    last = ts[i];
  }
  return last;
}
