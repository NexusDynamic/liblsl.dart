import 'dart:convert';
import 'dart:typed_data';

import 'package:peer_coordinator/framework.dart';

/// Wire protocol version. Bumped on any incompatible framing change.
const int wsProtocolVersion = 1;

/// Control-frame types.
///
/// Control traffic is JSON text; data samples use the binary frame below.
enum WsControl {
  /// client -> hub: "here is who I am". Carries a [PeerDescriptor].
  hello,

  /// hub -> client: assigns a connection id and a numeric slot.
  welcome,

  /// client -> hub: republish my descriptor (role changed after election).
  update,

  /// client -> hub: run a [DiscoveryQuery], optionally continuously.
  query,

  /// hub -> client: peers matching a query.
  queryResult,

  /// client -> hub: stop a continuous query.
  unquery,

  /// client -> hub: deliver this producer's stream to me.
  subscribe,

  /// client -> hub -> subscribers: a coordination message (JSON payload).
  message,

  /// hub -> client: a peer this client cared about has gone.
  peerGone,
}

/// A control frame.
class WsFrame {
  const WsFrame(this.type, this.payload);

  final WsControl type;
  final Map<String, dynamic> payload;

  String encode() =>
      jsonEncode({'v': wsProtocolVersion, 't': type.name, 'p': payload});

  /// Parses a control frame.
  ///
  /// Throws [FormatException] on anything malformed or from an incompatible
  /// protocol version — a hub must not guess at frames it does not understand.
  static WsFrame decode(String text) {
    final Object? raw = jsonDecode(text);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Control frame must be a JSON object');
    }
    final version = raw['v'];
    if (version != wsProtocolVersion) {
      throw FormatException(
        'Unsupported protocol version $version '
        '(this build speaks $wsProtocolVersion)',
      );
    }
    final typeName = raw['t'];
    final type = WsControl.values.where((c) => c.name == typeName).firstOrNull;
    if (type == null) {
      throw FormatException('Unknown control frame type: $typeName');
    }
    final payload = raw['p'];
    return WsFrame(type, payload is Map<String, dynamic> ? payload : const {});
  }
}

/// Binary framing for data-stream samples.
///
/// Data streams are the latency-critical path, and their shape is already
/// fixed and known to both ends from the negotiated [DataStreamConfig] — so
/// nothing per-sample needs describing and JSON would be pure overhead. An
/// 8-channel float64 sample is 78 bytes here versus 200+ as JSON, and the
/// receiver can read the payload as a typed list without parsing.
///
/// Layout (little-endian):
/// ```
///  0      uint8    frame kind (always kindSample)
///  1      uint8    StreamDataType.index
///  2..3   uint16   streamSlot   negotiated per stream; no name per sample
///  4..5   uint16   srcSlot      REWRITTEN BY THE HUB on relay
///  6..13  float64  senderMicros sender's clock, mirrors lsl_timestamp
/// 14..    payload  channels x sizeof(dtype)
///                  (string: uint32 length + utf8, per channel)
/// ```
///
/// The hub never parses the payload: it overwrites two bytes at offset 4 and
/// forwards the same buffer to every subscriber. That is what keeps relay cost
/// near zero and is the whole justification for a dumb hub.
abstract final class WsSampleFrame {
  static const int kindSample = 0x01;
  static const int headerBytes = 14;

  static const int _kindOffset = 0;
  static const int _dtypeOffset = 1;
  static const int _streamSlotOffset = 2;
  static const int _srcSlotOffset = 4;
  static const int _microsOffset = 6;

  /// Whether [bytes] looks like a sample frame rather than control text.
  static bool isSample(Uint8List bytes) =>
      bytes.isNotEmpty && bytes[_kindOffset] == kindSample;

  static Uint8List encode({
    required StreamDataType dataType,
    required int streamSlot,
    required int srcSlot,
    required double senderMicros,
    required List<Object?> channels,
  }) {
    final body = _encodeBody(dataType, channels);
    final out = Uint8List(headerBytes + body.lengthInBytes);
    final view = ByteData.view(out.buffer);
    out[_kindOffset] = kindSample;
    out[_dtypeOffset] = dataType.index;
    view.setUint16(_streamSlotOffset, streamSlot, Endian.little);
    view.setUint16(_srcSlotOffset, srcSlot, Endian.little);
    view.setFloat64(_microsOffset, senderMicros, Endian.little);
    out.setRange(
      headerBytes,
      out.length,
      body.buffer.asUint8List(body.offsetInBytes, body.lengthInBytes),
    );
    return out;
  }

  /// Rewrites the source slot in place, without copying or parsing.
  ///
  /// The hub's entire per-sample cost.
  static void rewriteSourceSlot(Uint8List frame, int srcSlot) {
    ByteData.view(
      frame.buffer,
      frame.offsetInBytes,
      frame.lengthInBytes,
    ).setUint16(_srcSlotOffset, srcSlot, Endian.little);
  }

  static int streamSlotOf(Uint8List frame) => ByteData.view(
    frame.buffer,
    frame.offsetInBytes,
    frame.lengthInBytes,
  ).getUint16(_streamSlotOffset, Endian.little);

  static int sourceSlotOf(Uint8List frame) => ByteData.view(
    frame.buffer,
    frame.offsetInBytes,
    frame.lengthInBytes,
  ).getUint16(_srcSlotOffset, Endian.little);

  static double senderMicrosOf(Uint8List frame) => ByteData.view(
    frame.buffer,
    frame.offsetInBytes,
    frame.lengthInBytes,
  ).getFloat64(_microsOffset, Endian.little);

  static StreamDataType dataTypeOf(Uint8List frame) =>
      StreamDataType.values[frame[_dtypeOffset]];

  /// Reads the channel values back out.
  static List<Object?> decodeChannels(Uint8List frame, int channelCount) {
    final dataType = dataTypeOf(frame);
    final view = ByteData.view(
      frame.buffer,
      frame.offsetInBytes + headerBytes,
      frame.lengthInBytes - headerBytes,
    );
    switch (dataType) {
      case StreamDataType.float32:
        return [
          for (var i = 0; i < channelCount; i++)
            view.getFloat32(i * 4, Endian.little),
        ];
      case StreamDataType.double64:
        return [
          for (var i = 0; i < channelCount; i++)
            view.getFloat64(i * 8, Endian.little),
        ];
      case StreamDataType.int8:
        return [for (var i = 0; i < channelCount; i++) view.getInt8(i)];
      case StreamDataType.int16:
        return [
          for (var i = 0; i < channelCount; i++)
            view.getInt16(i * 2, Endian.little),
        ];
      case StreamDataType.int32:
        return [
          for (var i = 0; i < channelCount; i++)
            view.getInt32(i * 4, Endian.little),
        ];
      case StreamDataType.int64:
        return [
          for (var i = 0; i < channelCount; i++)
            view.getInt64(i * 8, Endian.little),
        ];
      case StreamDataType.string:
        final values = <String>[];
        var offset = 0;
        for (var i = 0; i < channelCount; i++) {
          final length = view.getUint32(offset, Endian.little);
          offset += 4;
          final bytes = Uint8List.view(
            view.buffer,
            view.offsetInBytes + offset,
            length,
          );
          values.add(utf8.decode(bytes));
          offset += length;
        }
        return values;
    }
  }

  static ByteData _encodeBody(StreamDataType dataType, List<Object?> channels) {
    switch (dataType) {
      case StreamDataType.float32:
        final data = ByteData(channels.length * 4);
        for (var i = 0; i < channels.length; i++) {
          data.setFloat32(
            i * 4,
            (channels[i] as num).toDouble(),
            Endian.little,
          );
        }
        return data;
      case StreamDataType.double64:
        final data = ByteData(channels.length * 8);
        for (var i = 0; i < channels.length; i++) {
          data.setFloat64(
            i * 8,
            (channels[i] as num).toDouble(),
            Endian.little,
          );
        }
        return data;
      case StreamDataType.int8:
        final data = ByteData(channels.length);
        for (var i = 0; i < channels.length; i++) {
          data.setInt8(i, channels[i] as int);
        }
        return data;
      case StreamDataType.int16:
        final data = ByteData(channels.length * 2);
        for (var i = 0; i < channels.length; i++) {
          data.setInt16(i * 2, channels[i] as int, Endian.little);
        }
        return data;
      case StreamDataType.int32:
        final data = ByteData(channels.length * 4);
        for (var i = 0; i < channels.length; i++) {
          data.setInt32(i * 4, channels[i] as int, Endian.little);
        }
        return data;
      case StreamDataType.int64:
        final data = ByteData(channels.length * 8);
        for (var i = 0; i < channels.length; i++) {
          data.setInt64(i * 8, channels[i] as int, Endian.little);
        }
        return data;
      case StreamDataType.string:
        final encoded = [
          for (final value in channels) utf8.encode(value as String),
        ];
        final total = encoded.fold<int>(0, (sum, b) => sum + 4 + b.length);
        final data = ByteData(total);
        var offset = 0;
        for (final bytes in encoded) {
          data.setUint32(offset, bytes.length, Endian.little);
          offset += 4;
          for (final byte in bytes) {
            data.setUint8(offset++, byte);
          }
        }
        return data;
    }
  }
}
