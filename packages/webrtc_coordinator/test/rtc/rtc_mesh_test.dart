/// The dial state machine, over a real hub and the fake adapter.
///
/// The hub is real because signalling is the half of this transport that still
/// goes through it, and `WsControl.signal`'s endpoint-ownership verification is
/// load-bearing — a fake hub would not enforce it.
@Tags(['integration'])
library;

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/websocket.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:test/test.dart';
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

void main() {
  late CoordinationHub hub;
  late Uri hubUri;
  late FakeRtcBus bus;
  late List<WsConnection> connections;
  late List<RtcMesh> meshes;

  const sessionName = 'RtcSession';
  const coordinationStream = 'coordination-test';

  setUp(() async {
    hub = await CoordinationHub.serve();
    hubUri = Uri.parse('ws://127.0.0.1:${hub.port}');
    bus = FakeRtcBus();
    connections = [];
    meshes = [];
  });

  tearDown(() async {
    for (final mesh in meshes) {
      await mesh.close();
    }
    for (final connection in connections) {
      await connection.close();
    }
    await hub.close();
  });

  /// A connected hub client with an announced signalling endpoint, plus a mesh.
  Future<RtcMesh> peer(String nodeUId) async {
    final connection = WsConnection(hubUri);
    await connection.connect();
    connections.add(connection);

    // The mesh signals as this endpoint, so the hub must agree it owns it.
    await connection.announce(
      PeerDescriptor(
        streamName: coordinationStream,
        sessionName: sessionName,
        nodeId: nodeUId,
        nodeUId: nodeUId,
        nodeRole: 'participant',
        endpointId: '$sessionName/$nodeUId/$coordinationStream',
      ),
      publish: false,
    );

    final mesh = RtcMesh(
      adapter: FakeRtcPeerAdapter(selfKey: nodeUId, bus: bus),
      connection: connection,
      selfNodeUId: nodeUId,
      sessionName: sessionName,
      coordinationStreamName: coordinationStream,
    );
    meshes.add(mesh);
    return mesh;
  }

  group('glare', () {
    test('the lexicographically lower uId offers', () async {
      final a = await peer('aaa');
      final b = await peer('zzz');
      expect(a.shouldOffer('zzz'), isTrue);
      expect(b.shouldOffer('aaa'), isFalse);
    });

    test('a simultaneous dial from both sides collapses to one link', () async {
      final a = await peer('aaa');
      final b = await peer('zzz');

      // Both want the same stream at the same moment. Only 'aaa' offers, so
      // there is exactly one negotiation and one connection per side.
      final results = await Future.wait([
        a.channelFor(peerNodeUId: 'zzz', streamName: 'Data'),
        b.channelFor(peerNodeUId: 'aaa', streamName: 'Data'),
      ]);

      expect(results, hasLength(2));
      expect(a.connectedPeers, ['zzz']);
      expect(b.connectedPeers, ['aaa']);
    });
  });

  group('dialling', () {
    test('a channel opens in both directions and carries messages', () async {
      final a = await peer('aaa');
      final b = await peer('bbb');

      final channels = await Future.wait([
        a.channelFor(peerNodeUId: 'bbb', streamName: 'Data'),
        b.channelFor(peerNodeUId: 'aaa', streamName: 'Data'),
      ]);
      final fromA = channels[0];
      final fromB = channels[1];

      final received = <Object>[];
      fromB.messages.listen(received.add);

      fromA.send('ping');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, ['ping']);
    });

    test('a second stream reuses the same connection', () async {
      final a = await peer('aaa');
      final b = await peer('bbb');

      await Future.wait([
        a.channelFor(peerNodeUId: 'bbb', streamName: coordinationStream),
        b.channelFor(peerNodeUId: 'aaa', streamName: coordinationStream),
      ]);
      await Future.wait([
        a.channelFor(peerNodeUId: 'bbb', streamName: 'Data'),
        b.channelFor(peerNodeUId: 'aaa', streamName: 'Data'),
      ]);

      // One peer entry, two channels on it: this is the "one RTCPeerConnection
      // per pair" rule holding.
      expect(a.connectedPeers, ['bbb']);
    });

    test(
      'the coordination stream is pinned to the reserved channel id',
      () async {
        final a = await peer('aaa');
        expect(a.channelIdFor(coordinationStream), coordinationChannelId);
        expect(
          a.channelIdFor('Data'),
          greaterThanOrEqualTo(reservedChannelIds),
        );
      },
    );

    test('dialling yourself is refused', () async {
      final a = await peer('aaa');
      expect(
        () => a.channelFor(peerNodeUId: 'aaa', streamName: 'Data'),
        throwsArgumentError,
      );
    });

    test('a peer that never answers times out rather than hanging', () async {
      final a = await peer('aaa');
      // 'zzz' has a hub endpoint so the signal is deliverable, but no mesh
      // behind it, so no answer ever comes.
      final connection = WsConnection(hubUri);
      await connection.connect();
      connections.add(connection);
      await connection.announce(
        PeerDescriptor(
          streamName: coordinationStream,
          sessionName: sessionName,
          nodeId: 'zzz',
          nodeUId: 'zzz',
          nodeRole: 'participant',
          endpointId: '$sessionName/zzz/$coordinationStream',
        ),
        publish: false,
      );

      final impatient = RtcMesh(
        adapter: FakeRtcPeerAdapter(selfKey: 'aaa-2', bus: bus),
        connection: a.connection,
        selfNodeUId: 'aaa',
        sessionName: sessionName,
        coordinationStreamName: coordinationStream,
        connectTimeout: const Duration(milliseconds: 300),
      );
      meshes.add(impatient);

      await expectLater(
        impatient.channelFor(peerNodeUId: 'zzz', streamName: 'Data'),
        throwsStateError,
      );
    });
  });

  group('release', () {
    test('the connection goes when its last channel does', () async {
      final a = await peer('aaa');
      final b = await peer('bbb');

      await Future.wait([
        a.channelFor(peerNodeUId: 'bbb', streamName: 'Data'),
        b.channelFor(peerNodeUId: 'aaa', streamName: 'Data'),
      ]);
      await Future.wait([
        a.channelFor(peerNodeUId: 'bbb', streamName: 'Other'),
        b.channelFor(peerNodeUId: 'aaa', streamName: 'Other'),
      ]);

      await a.releaseChannel(peerNodeUId: 'bbb', streamName: 'Data');
      expect(a.connectedPeers, [
        'bbb',
      ], reason: 'one channel left, so the connection stays');

      await a.releaseChannel(peerNodeUId: 'bbb', streamName: 'Other');
      expect(
        a.connectedPeers,
        isEmpty,
        reason: 'last channel gone, so the RTCPeerConnection must go too',
      );
    });

    test('releasing a channel that is not there is a no-op', () async {
      final a = await peer('aaa');
      await a.releaseChannel(peerNodeUId: 'nobody', streamName: 'Data');
    });

    test('a bye tells the far side to let go', () async {
      final a = await peer('aaa');
      final b = await peer('bbb');

      await Future.wait([
        a.channelFor(peerNodeUId: 'bbb', streamName: 'Data'),
        b.channelFor(peerNodeUId: 'aaa', streamName: 'Data'),
      ]);
      expect(b.connectedPeers, ['aaa']);

      final lost = b.peerLost.first;
      await a.releasePeer('bbb');

      expect(await lost.timeout(const Duration(seconds: 2)), 'aaa');
      expect(b.connectedPeers, isEmpty);
    });
  });

  group('signal validation', () {
    test(
      'a signal whose envelope contradicts the verified sender is dropped',
      () async {
        final a = await peer('aaa');
        final b = await peer('bbb');

        await Future.wait([
          a.channelFor(peerNodeUId: 'bbb', streamName: 'Data'),
          b.channelFor(peerNodeUId: 'aaa', streamName: 'Data'),
        ]);

        // 'bbb' claims to be 'ccc'. The hub stamps the real `from`, so the
        // mismatch is detectable — and must not be acted on.
        b.connection.sendSignal(
          fromEndpointId: '$sessionName/bbb/$coordinationStream',
          toEndpointId: '$sessionName/aaa/$coordinationStream',
          payload: const RtcSignal(
            kind: RtcSignalKind.bye,
            fromNodeUId: 'ccc',
          ).toJson(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(a.connectedPeers, [
          'bbb',
        ], reason: 'a forged bye must not tear down a real link');
      },
    );

    test('an unparseable payload does not kill the listener', () async {
      final a = await peer('aaa');
      final b = await peer('bbb');

      b.connection.sendSignal(
        fromEndpointId: '$sessionName/bbb/$coordinationStream',
        toEndpointId: '$sessionName/aaa/$coordinationStream',
        payload: {'nonsense': true},
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Still able to negotiate afterwards.
      final channels = await Future.wait([
        a.channelFor(peerNodeUId: 'bbb', streamName: 'Data'),
        b.channelFor(peerNodeUId: 'aaa', streamName: 'Data'),
      ]);
      expect(channels, hasLength(2));
    });
  });
}
