/// The hub's one unicast: forwarding an opaque payload between two peers.
///
/// This is what demotes the hub from relay to post box. A peer-to-peer
/// transport uses it to exchange whatever the two ends need to dial each other
/// — a WebRTC offer, an answer, an ICE candidate — after which its data never
/// touches the hub. That exchange cannot ride the coordination stream, because
/// the coordination stream is the thing being established.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:peer_coordinator/testing.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/websocket.dart';
import 'package:test/test.dart';

void main() {
  late TestHub testHub;
  late List<WsConnection> connections;

  setUp(() async {
    testHub = await startTestHub(session: 'SignalSession');
    connections = [];
  });

  tearDown(() async {
    for (final connection in connections) {
      await connection.close();
    }
    connections = [];
    await testHub.close();
  });

  /// A connected node with one announced endpoint, as a stream would announce it.
  Future<WsConnection> peer(String nodeUId) async {
    final connection = await testHub.connect(nodeUId);
    connections.add(connection);
    await connection.announce(
      PeerDescriptor.forNode(
        streamName: 'coordination',
        sessionName: 'SignalSession',
        node: ParticipantNode(
          NodeConfig(name: nodeUId, id: nodeUId, uId: nodeUId),
        ),
      ),
    );
    return connection;
  }

  String endpointOf(String nodeUId) => 'SignalSession/$nodeUId/coordination';

  test('a payload reaches the endpoint it names', () async {
    final alice = await peer('alice');
    final bob = await peer('bob');

    final received = bob.signals.first.timeout(const Duration(seconds: 5));
    alice.sendSignal(
      fromEndpointId: endpointOf('alice'),
      toEndpointId: endpointOf('bob'),
      payload: {'kind': 'offer', 'sdp': 'v=0...'},
    );

    final signal = await received;
    expect(signal.fromEndpointId, endpointOf('alice'));
    expect(signal.toEndpointId, endpointOf('bob'));
    expect((signal.payload! as Map)['kind'], 'offer');
    expect((signal.payload! as Map)['sdp'], 'v=0...');
  });

  test('the hub does not look inside the payload', () async {
    // Nested, mixed, and nothing the hub could have a schema for — the point
    // being that two peers can put whatever they like in here.
    final alice = await peer('alice');
    final bob = await peer('bob');

    final received = bob.signals.first.timeout(const Duration(seconds: 5));
    alice.sendSignal(
      fromEndpointId: endpointOf('alice'),
      toEndpointId: endpointOf('bob'),
      payload: {
        'candidates': [
          {'sdpMLineIndex': 0, 'candidate': 'candidate:1 1 udp 2130706431 ...'},
          {'sdpMLineIndex': 1, 'candidate': null},
        ],
        'unicode': 'ünïcødé ✓',
      },
    );

    final payload = (await received).payload! as Map;
    expect(payload['unicode'], 'ünïcødé ✓');
    expect((payload['candidates'] as List), hasLength(2));
    expect((payload['candidates'] as List)[1]['candidate'], isNull);
  });

  test('only the addressed peer sees it', () async {
    final alice = await peer('alice');
    final bob = await peer('bob');
    final carol = await peer('carol');

    final atCarol = <WsSignal>[];
    carol.signals.listen(atCarol.add);
    final atBob = bob.signals.first.timeout(const Duration(seconds: 5));

    alice.sendSignal(
      fromEndpointId: endpointOf('alice'),
      toEndpointId: endpointOf('bob'),
      payload: 'for bob only',
    );

    await atBob;
    // Settle, so a stray delivery to carol would have landed by now.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(atCarol, isEmpty);
  });

  test('a connection cannot signal as an endpoint it does not own', () async {
    // Otherwise any peer could impersonate any other during connection setup,
    // which is the one moment where identity actually matters.
    final alice = await peer('alice');
    final bob = await peer('bob');
    final carol = await peer('carol');

    final atCarol = <WsSignal>[];
    carol.signals.listen(atCarol.add);

    alice.sendSignal(
      fromEndpointId: endpointOf('bob'), // not alice's to claim
      toEndpointId: endpointOf('carol'),
      payload: 'pretending to be bob',
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(atCarol, isEmpty);
    // The hub stays up for everyone else.
    final legitimate = carol.signals.first.timeout(const Duration(seconds: 5));
    bob.sendSignal(
      fromEndpointId: endpointOf('bob'),
      toEndpointId: endpointOf('carol'),
      payload: 'really bob',
    );
    expect((await legitimate).payload, 'really bob');
  });

  test('signalling an unknown endpoint is dropped, not fatal', () async {
    final alice = await peer('alice');
    final bob = await peer('bob');

    alice.sendSignal(
      fromEndpointId: endpointOf('alice'),
      toEndpointId: endpointOf('nobody-here'),
      payload: 'into the void',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The connection is still good afterwards.
    final received = bob.signals.first.timeout(const Duration(seconds: 5));
    alice.sendSignal(
      fromEndpointId: endpointOf('alice'),
      toEndpointId: endpointOf('bob'),
      payload: 'still here',
    );
    expect((await received).payload, 'still here');
  });

  test('signalling is bidirectional over the same sockets', () async {
    // An offer/answer exchange is the shape this exists for.
    final alice = await peer('alice');
    final bob = await peer('bob');

    final offerAtBob = bob.signals.first.timeout(const Duration(seconds: 5));
    alice.sendSignal(
      fromEndpointId: endpointOf('alice'),
      toEndpointId: endpointOf('bob'),
      payload: {'kind': 'offer'},
    );
    expect(((await offerAtBob).payload! as Map)['kind'], 'offer');

    final answerAtAlice = alice.signals.first.timeout(
      const Duration(seconds: 5),
    );
    bob.sendSignal(
      fromEndpointId: endpointOf('bob'),
      toEndpointId: endpointOf('alice'),
      payload: {'kind': 'answer'},
    );
    expect(((await answerAtAlice).payload! as Map)['kind'], 'answer');
  });
}
