/// The LSL bridge protocol: LSL streams over a WebSocket.
///
/// Connecting: `ws://host:port/?v=3&token=<token>` (`v` is
/// [bridgeProtocol]; the token only when the bridge has one). A plain HTTP
/// GET of the same URL answers `{"streams": [...], "accepts_publish": bool}`.
///
/// Text frames are JSON control messages:
/// - server → client `{"type": "streams", "protocol": 3, "streams": [...],
///   "accepts_publish": bool}`: the streams shared ([BridgeStream.toJson]),
///   sent on connecting and again whenever they change (a stream shared or
///   gone, a client publishing or leaving). Ids are never reused.
/// - client → server `{"type": "subscribe", "ids": [...]}`: the streams to
///   send (replaces the previous subscription);
/// - client → server `{"type": "ping", "t": t0, "wave": n}`, answered by
///   `{"type": "pong", "t": t0, "wave": n, "t1": ..., "t2": ...}` (the
///   server's clock when the ping arrived and when the answer left), from
///   which the client estimates the server's clock against its own. The
///   server estimates nothing, like an LSL outlet.
/// - both ways `{"type": "timing", "id": n, "hops": [...]}`: how that
///   stream's time stamps map onto the **server's** clock, as a
///   `ClockChain`: one hop per clock crossed so far, each with its offset,
///   drift, error bound and measured latency. The server sends it for the
///   streams a client subscribes to, when it subscribes and every few
///   seconds; a publishing client sends it for its streams before their
///   first samples and whenever its estimate changes (`"hops": []` if its
///   time stamps are on the server's clock already).
/// - client → server `{"type": "publish", "streams": [...]}`: streams the
///   client will send samples of, with ids of its choosing. A bridge that
///   accepts published streams shares each with every client (as a new id)
///   and may also make it an LSL outlet on its computer. It answers
///   `{"type": "published", "ids": [...], "shared_ids": {...},
///   "errors": {...}}`: the ids it took, what each is shared as (client id
///   to shared id), and why the others were refused (by client id).
/// - client → server `{"type": "unpublish", "ids": [...]}`: stop
///   publishing (also when the client disconnects).
///
/// Binary frames are samples ([encodeSamples]): from server to client for
/// subscribed streams, and from client to server for published ones (under
/// the client's id). Their time stamps are the ones the stream's origin
/// gave them and are never changed on the way; the `timing` messages say
/// how to read them. Values travel in the stream's own channel format
/// (int64 is exact to 2^53 where ints are JavaScript numbers).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:lsl_core/lsl_core.dart';

/// The protocol version spoken here. Version 1 sent time stamps on the
/// server's clock, version 2 every value as float32, so none of them can be
/// mixed.
const bridgeProtocol = 3;

/// A shared stream, as the server describes it.
class BridgeStream {
  final int id;
  final LslStreamDescription description;
  final List<LSLChannel> channels;
  final String xml;

  const BridgeStream(this.id, this.description, this.channels, this.xml);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': description.name,
    'type': description.type,
    'channel_count': description.channelCount,
    'rate': description.rate,
    'format': description.format.name,
    'source_id': description.sourceId,
    'hostname': description.hostname,
    'uid': description.uid,
    'labels': [for (final c in channels) c.label],
    'units': [for (final c in channels) c.unit],
    'types': [for (final c in channels) c.type],
    'xml': xml,
  };

  /// [host] is where the bridge is, shown as the stream's host.
  static BridgeStream fromJson(Map<String, Object?> j, {String host = ''}) {
    List<String> strings(Object? o) => [
      for (final v in (o as List?) ?? const []) '$v',
    ];
    final labels = strings(j['labels']);
    final units = strings(j['units']);
    final types = strings(j['types']);
    final sourceHost = j['hostname'] as String? ?? '';
    return BridgeStream(
      (j['id']! as num).toInt(),
      LslStreamDescription(
        name: j['name']! as String,
        type: j['type'] as String? ?? '',
        channelCount: (j['channel_count']! as num).toInt(),
        rate: (j['rate'] as num? ?? 0).toDouble(),
        format: LSLChannelFormat.values.byName(j['format']! as String),
        sourceId: j['source_id'] as String? ?? '',
        hostname: host.isEmpty ? sourceHost : '$sourceHost via $host',
        uid: 'bridge:$host:${j['uid'] ?? j['id']}',
        xml: j['xml'] as String? ?? '',
      ),
      [
        for (var c = 0; c < labels.length; c++)
          LSLChannel(
            labels[c],
            unit: c < units.length ? units[c] : '',
            type: c < types.length ? types[c] : '',
          ),
      ],
      j['xml'] as String? ?? '',
    );
  }
}

/// The value kind in a samples frame (its byte 12) of each format.
const _kinds = [
  LSLChannelFormat.float32,
  LSLChannelFormat.string,
  LSLChannelFormat.double64,
  LSLChannelFormat.int8,
  LSLChannelFormat.int16,
  LSLChannelFormat.int32,
  LSLChannelFormat.int64,
];

/// A binary samples frame: stream id, sample count, channel count, value
/// kind (0 float32, 1 string, 2 double64, 3 int8, 4 int16, 5 int32,
/// 6 int64), time stamps, then the values, little-endian, or, per string, a
/// uint32 byte length and UTF-8 bytes. Numeric values are written in
/// [format] (the stream's), from [LslChunk.typed] if there is one.
Uint8List encodeSamples(
  int id,
  LslChunk c,
  int channels, [
  LSLChannelFormat format = LSLChannelFormat.float32,
]) {
  final n = c.length;
  final strings = c.strings;
  final encoded = strings == null
      ? null
      : [for (final s in strings) utf8.encode(s)];
  final f = encoded == null ? format.outletFormat : LSLChannelFormat.string;
  final count = n * channels;
  final size =
      13 +
      8 * n +
      (encoded == null
          ? f.byteWidth * count
          : encoded.fold<int>(0, (a, b) => a + 4 + b.length));
  final out = Uint8List(size);
  final d = ByteData.sublistView(out);
  d.setUint32(0, id, Endian.little);
  d.setUint32(4, n, Endian.little);
  d.setUint32(8, channels, Endian.little);
  d.setUint8(12, _kinds.indexOf(f));
  var p = 13;
  for (var i = 0; i < n; i++, p += 8) {
    d.setFloat64(p, c.times[i], Endian.little);
  }
  if (encoded != null) {
    for (final b in encoded) {
      d.setUint32(p, b.length, Endian.little);
      out.setAll(p + 4, b);
      p += 4 + b.length;
    }
    return out;
  }
  writeValues(d, p, f, (c.typed ?? c.values!) as List<num>, count);
  return out;
}

/// The last time stamp in a samples frame, or null if it has none.
double? lastTimeOf(Uint8List bytes) {
  if (bytes.length < 13) return null;
  final d = ByteData.sublistView(bytes);
  final n = d.getUint32(4, Endian.little);
  final p = 13 + 8 * (n - 1);
  if (n == 0 || p + 8 > bytes.length) return null;
  return d.getFloat64(p, Endian.little);
}

/// Decode [encodeSamples]; [received] is when the frame arrived. Numeric
/// values come as [LslChunk.values] (a [Float32List] for float32, else a
/// [Float64List]) and, in their own format, [LslChunk.typed] (but for int64
/// where ints are JavaScript numbers).
(int id, LslChunk chunk) decodeSamples(Uint8List bytes, {double? received}) {
  final d = ByteData.sublistView(bytes);
  final id = d.getUint32(0, Endian.little);
  final n = d.getUint32(4, Endian.little);
  final channels = d.getUint32(8, Endian.little);
  final kind = d.getUint8(12);
  if (kind >= _kinds.length) {
    throw FormatException('Unknown value kind $kind');
  }
  final f = _kinds[kind];
  var p = 13;
  final times = Float64List(n);
  for (var i = 0; i < n; i++, p += 8) {
    times[i] = d.getFloat64(p, Endian.little);
  }
  final count = n * channels;
  if (f == LSLChannelFormat.string) {
    final strings = <String>[];
    for (var i = 0; i < count; i++) {
      final len = d.getUint32(p, Endian.little);
      strings.add(
        utf8.decode(Uint8List.sublistView(bytes, p + 4, p + 4 + len)),
      );
      p += 4 + len;
    }
    return (id, LslChunk(times, strings: strings, received: received));
  }
  final typed = readValues(d, p, f, count);
  return (
    id,
    LslChunk(
      times,
      values: asDoubles(typed),
      // An int64 list where ints are JavaScript numbers is doubles already.
      typed: f == LSLChannelFormat.int64 && !exactInt64 ? null : typed,
      received: received,
    ),
  );
}
