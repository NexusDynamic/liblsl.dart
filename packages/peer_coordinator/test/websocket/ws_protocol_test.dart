/// Tests for the WebSocket wire format.
///
/// Pure encode/decode — no sockets, no hub. Framing bugs are miserable to
/// diagnose through a live connection, so they get pinned here first.
library;

import 'dart:typed_data';

import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/src/websocket/ws_protocol.dart';
import 'package:test/test.dart';

PeerDescriptor descriptor({
  String uId = 'uid-1',
  String role = 'participant',
}) => PeerDescriptor(
  streamName: 'coordination',
  sessionName: 'S',
  nodeId: 'node-1',
  nodeUId: uId,
  nodeRole: role,
  capabilities: {'coordinator', 'participant'},
  randomRoll: 0.25,
  startedAt: '2026-08-09T12:00:00.000',
  endpointId: 'S/$uId/coordination',
);

void main() {
  group('control frames', () {
    test('round-trip preserves type and payload', () {
      final frame = WsFrame(WsControl.hello, descriptor().toJson());
      final decoded = WsFrame.decode(frame.encode());

      expect(decoded.type, WsControl.hello);
      final peer = PeerDescriptor.fromJson(decoded.payload);
      expect(peer.nodeUId, 'uid-1');
      expect(peer.nodeRole, 'participant');
      expect(peer.capabilities, {'coordinator', 'participant'});
      expect(peer.randomRoll, 0.25);
      expect(peer.startedAt, '2026-08-09T12:00:00.000');
      expect(peer.endpointId, 'S/uid-1/coordination');
    });

    test('a DiscoveryQuery survives the wire', () {
      // The hub evaluates queries itself, so they have to serialise exactly.
      final query = PeerQueries.election(
        streamName: 'coordination',
        sessionName: 'S',
        excludeNodeUId: 'uid-1',
        isRandomStrategy: true,
        myRandomRoll: 0.5,
      );
      final decoded = WsFrame.decode(
        WsFrame(WsControl.query, {'qid': 1, 'query': query.toJson()}).encode(),
      );
      final restored = DiscoveryQuery.fromJson(
        decoded.payload['query'] as Map<String, dynamic>,
      );

      // Same verdicts as the original on both sides of the boundary.
      final me = descriptor(uId: 'uid-1', role: 'coordinator');
      final other = descriptor(uId: 'uid-2', role: 'coordinator');
      expect(restored.matches(me), query.matches(me));
      expect(restored.matches(other), query.matches(other));
      expect(restored.matches(other), isTrue);
      expect(restored.matches(me), isFalse);
    });

    test('a mismatched protocol version is rejected, not guessed at', () {
      expect(
        () => WsFrame.decode('{"v":999,"t":"hello","p":{}}'),
        throwsFormatException,
      );
    });

    test('an unknown frame type is rejected', () {
      // The version has to be the current one, or this would pass for the wrong
      // reason — rejected as an old protocol rather than an unknown type.
      expect(
        () => WsFrame.decode(
          '{"v":$wsProtocolVersion,"t":"teleport","p":{}}',
        ),
        throwsFormatException,
      );
    });

    test('the previous protocol version is rejected', () {
      // v2 added the signal frame. Decode refuses anything it does not fully
      // understand rather than guessing, so a hub and its clients have to be
      // deployed together — this is the test that says so out loud.
      expect(wsProtocolVersion, 2);
      expect(
        () => WsFrame.decode('{"v":1,"t":"hello","p":{}}'),
        throwsFormatException,
      );
    });

    test('a signal frame round-trips', () {
      final frame = WsFrame(WsControl.signal, {
        'from': 'S/a/coordination',
        'to': 'S/b/coordination',
        'payload': {'kind': 'offer', 'sdp': 'v=0'},
      });
      final decoded = WsFrame.decode(frame.encode());
      expect(decoded.type, WsControl.signal);
      expect(decoded.payload['from'], 'S/a/coordination');
      expect((decoded.payload['payload'] as Map)['kind'], 'offer');
    });

    test('non-object JSON is rejected', () {
      expect(() => WsFrame.decode('[1,2,3]'), throwsFormatException);
    });
  });

  group('binary sample frames', () {
    test('float64 round-trips bit-exactly', () {
      const values = [1.5, -2.25, 3.14159265358979, 0.0];
      final frame = WsSampleFrame.encode(
        dataType: StreamDataType.double64,
        streamSlot: 7,
        srcSlot: 3,
        senderMicros: 1234567.5,
        channels: values,
      );

      expect(WsSampleFrame.isSample(frame), isTrue);
      expect(WsSampleFrame.streamSlotOf(frame), 7);
      expect(WsSampleFrame.sourceSlotOf(frame), 3);
      expect(WsSampleFrame.senderMicrosOf(frame), 1234567.5);
      expect(WsSampleFrame.dataTypeOf(frame), StreamDataType.double64);
      expect(WsSampleFrame.decodeChannels(frame, 4), values);
    });

    test('an 8-channel float64 sample is 78 bytes', () {
      // Pinning the size because it is the reason this is binary at all:
      // the same sample as JSON is 200+ bytes.
      final frame = WsSampleFrame.encode(
        dataType: StreamDataType.double64,
        streamSlot: 0,
        srcSlot: 0,
        senderMicros: 0,
        channels: List<double>.filled(8, 1.0),
      );
      expect(frame.length, 14 + 8 * 8);
      expect(frame.length, 78);
    });

    test('every numeric type round-trips at its range limits', () {
      final cases = <StreamDataType, List<Object?>>{
        StreamDataType.float32: [1.5, -1.5],
        StreamDataType.double64: [double.maxFinite, -double.maxFinite],
        StreamDataType.int8: [127, -128],
        StreamDataType.int16: [32767, -32768],
        StreamDataType.int32: [2147483647, -2147483648],
        StreamDataType.int64: [9007199254740991, -9007199254740991],
      };
      cases.forEach((dataType, values) {
        final frame = WsSampleFrame.encode(
          dataType: dataType,
          streamSlot: 1,
          srcSlot: 1,
          senderMicros: 0,
          channels: values,
        );
        expect(
          WsSampleFrame.decodeChannels(frame, values.length),
          values,
          reason: '$dataType should round-trip',
        );
      });
    });

    test('strings round-trip with unicode, quotes and newlines', () {
      const values = ["it's", 'a "test"\nwith 日本語', ''];
      final frame = WsSampleFrame.encode(
        dataType: StreamDataType.string,
        streamSlot: 2,
        srcSlot: 5,
        senderMicros: 42.0,
        channels: values,
      );
      expect(WsSampleFrame.decodeChannels(frame, 3), values);
    });

    test('rewriting the source slot changes nothing else', () {
      const values = [1.0, 2.0, 3.0];
      final frame = WsSampleFrame.encode(
        dataType: StreamDataType.double64,
        streamSlot: 11,
        srcSlot: 0,
        senderMicros: 99.5,
        channels: values,
      );
      final before = Uint8List.fromList(frame);

      WsSampleFrame.rewriteSourceSlot(frame, 65535);

      expect(WsSampleFrame.sourceSlotOf(frame), 65535);
      expect(WsSampleFrame.streamSlotOf(frame), 11);
      expect(WsSampleFrame.senderMicrosOf(frame), 99.5);
      expect(WsSampleFrame.decodeChannels(frame, 3), values);
      // Only the two slot bytes may differ.
      for (var i = 0; i < frame.length; i++) {
        if (i == 4 || i == 5) continue;
        expect(frame[i], before[i], reason: 'byte $i must not change');
      }
    });

    test('control text is not mistaken for a sample frame', () {
      final text = WsFrame(WsControl.hello, const {}).encode();
      expect(
        WsSampleFrame.isSample(Uint8List.fromList(text.codeUnits)),
        isFalse,
      );
    });
  });
}
