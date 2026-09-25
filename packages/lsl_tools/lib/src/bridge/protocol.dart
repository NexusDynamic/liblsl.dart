/// The LSL bridge protocol: LSL streams over a WebSocket.
///
/// Connecting: `ws://host:port/?token=<token>` (the token only when the
/// bridge has one). A plain HTTP GET of the same URL answers
/// `{"streams": [...], "accepts_publish": bool}`.
///
/// Text frames are JSON control messages:
/// - server → client `{"type": "streams", "streams": [...],
///   "accepts_publish": bool}`: the streams shared ([BridgeStream.toJson]),
///   sent on connecting and again whenever they change (a stream shared or
///   gone, a client publishing or leaving). Ids are never reused.
/// - client → server `{"type": "subscribe", "ids": [...]}`: the streams to
///   send (replaces the previous subscription);
/// - client → server `{"type": "ping", "t": <client time>}`, answered by
///   `{"type": "pong", "t": <the same>, "server": <server time>}`, which
///   the client uses to map the server's clock onto its own.
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
/// Binary frames are samples ([encodeSamples]) with time stamps on the
/// server's clock: from server to client for subscribed streams, and from
/// client to server for published ones (under the client's id). Values
/// travel as float32.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../lsl_types.dart';

/// A shared stream, as the server describes it.
class BridgeStream {
  final int id;
  final LslStreamDescription description;
  final List<LslChannel> channels;
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
        format: LslFormat.values.byName(j['format']! as String),
        sourceId: j['source_id'] as String? ?? '',
        hostname: host.isEmpty ? sourceHost : '$sourceHost via $host',
        uid: 'bridge:$host:${j['uid'] ?? j['id']}',
        xml: j['xml'] as String? ?? '',
      ),
      [
        for (var c = 0; c < labels.length; c++)
          LslChannel(
            labels[c],
            unit: c < units.length ? units[c] : '',
            type: c < types.length ? types[c] : '',
          ),
      ],
      j['xml'] as String? ?? '',
    );
  }
}

/// A binary samples frame: stream id, sample count, channel count, kind
/// (0 numeric, 1 strings), time stamps, then float32 values or, per value,
/// a uint32 byte length and UTF-8 bytes.
Uint8List encodeSamples(int id, LslChunk c, int channels) {
  final n = c.length;
  final strings = c.strings;
  final encoded = strings == null
      ? null
      : [for (final s in strings) utf8.encode(s)];
  final size =
      13 +
      8 * n +
      (encoded == null
          ? 4 * n * channels
          : encoded.fold<int>(0, (a, b) => a + 4 + b.length));
  final out = Uint8List(size);
  final d = ByteData.sublistView(out);
  d.setUint32(0, id, Endian.little);
  d.setUint32(4, n, Endian.little);
  d.setUint32(8, channels, Endian.little);
  d.setUint8(12, encoded == null ? 0 : 1);
  var p = 13;
  for (var i = 0; i < n; i++, p += 8) {
    d.setFloat64(p, c.times[i], Endian.little);
  }
  if (encoded == null) {
    final v = c.values!;
    for (var i = 0; i < n * channels; i++, p += 4) {
      d.setFloat32(p, v[i], Endian.little);
    }
  } else {
    for (final b in encoded) {
      d.setUint32(p, b.length, Endian.little);
      out.setAll(p + 4, b);
      p += 4 + b.length;
    }
  }
  return out;
}

/// Decode [encodeSamples]; time stamps are shifted by [offset].
(int id, LslChunk chunk) decodeSamples(Uint8List bytes, {double offset = 0}) {
  final d = ByteData.sublistView(bytes);
  final id = d.getUint32(0, Endian.little);
  final n = d.getUint32(4, Endian.little);
  final channels = d.getUint32(8, Endian.little);
  final kind = d.getUint8(12);
  var p = 13;
  final times = Float64List(n);
  for (var i = 0; i < n; i++, p += 8) {
    times[i] = d.getFloat64(p, Endian.little) + offset;
  }
  if (kind == 0) {
    final values = Float32List(n * channels);
    for (var i = 0; i < n * channels; i++, p += 4) {
      values[i] = d.getFloat32(p, Endian.little);
    }
    return (id, LslChunk(times, values: values));
  }
  final strings = <String>[];
  for (var i = 0; i < n * channels; i++) {
    final len = d.getUint32(p, Endian.little);
    strings.add(utf8.decode(Uint8List.sublistView(bytes, p + 4, p + 4 + len)));
    p += 4 + len;
  }
  return (id, LslChunk(times, strings: strings));
}
