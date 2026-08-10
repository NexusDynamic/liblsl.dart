/// Drives real coordination sessions over a real WebSocket hub.
///
/// The hub runs in-process on an ephemeral port, so these are fast and can run
/// in parallel, but the traffic is genuine sockets — control frames as JSON
/// text and samples as binary.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/websocket.dart';
import 'package:test/test.dart';

void main() {
  late CoordinationHub hub;
  late Uri hubUri;
  late List<PeerSession> sessions;

  setUp(() async {
    hub = await CoordinationHub.serve();
    hubUri = Uri.parse('ws://127.0.0.1:${hub.port}');
    sessions = [];
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      try {
        await session.leave();
      } catch (_) {
        // Teardown must not mask the assertion that actually failed.
      }
      try {
        await session.dispose();
      } catch (_) {}
    }
    sessions = [];
    await hub.close();
  });

  CoordinationConfig configFor({int maxNodes = 3}) => CoordinationConfig(
    name: 'ws_test',
    sessionConfig: CoordinationSessionConfig(
      name: 'WsSession',
      maxNodes: maxNodes,
      minNodes: 1,
      heartbeatInterval: const Duration(milliseconds: 100),
      discoveryInterval: const Duration(milliseconds: 50),
      nodeTimeout: const Duration(milliseconds: 800),
      consumeCoordinationStreamAsCoordinator: false,
    ),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: maxNodes,
    ),
    streamConfig: CoordinationStreamConfig(name: 'coordination'),
    transportConfig: WebSocketTransportConfig(hubUri: hubUri),
  );

  /// Lower roll wins the election.
  Future<PeerSession> joined(
    String name, {
    required double randomRoll,
    int maxNodes = 3,
  }) async {
    final session = PeerSession.create(
      configFor(maxNodes: maxNodes),
      thisNodeConfig: NodeConfig(
        name: name,
        id: name,
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
        metadata: {PeerMetadataKeys.randomRoll: randomRoll.toString()},
      ),
    );
    sessions.add(session);
    await session.initialize();
    await session.join(const Duration(seconds: 2));
    return session;
  }

  group('hub', () {
    test('rejects a plain HTTP request instead of hanging', () async {
      // A misconfigured client should get a clear error, not a dead socket.
      final client = HttpClient();
      final request = await client.getUrl(hubUri.replace(scheme: 'http'));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('accepts a connection and assigns a slot', () async {
      final connection = WsConnection(hubUri);
      await connection.connect();

      final slot = await connection.announce(
        PeerDescriptor(
          streamName: 'coordination',
          sessionName: 'WsSession',
          nodeId: 'n1',
          nodeUId: 'uid-1',
          nodeRole: 'participant',
          endpointId: 'WsSession/uid-1/coordination',
        ),
      );

      expect(slot, greaterThan(0));
      expect(hub.endpointCount, 1);
      await connection.close();
    });
  });

  group('election', () {
    test('a lone node becomes coordinator', () async {
      final only = await joined('solo', randomRoll: 0.5);
      expect(only.isCoordinator, isTrue);
    });

    test('two nodes agree on exactly one coordinator', () async {
      final first = await joined('first', randomRoll: 0.1);
      expect(first.isCoordinator, isTrue);

      final second = await joined('second', randomRoll: 0.9);
      expect(second.isCoordinator, isFalse);

      await first.waitForMinNodes(2, timeout: const Duration(seconds: 5));
      expect(first.connectedNodes, hasLength(2));
      expect(second.coordinatorUId, first.thisNode.uId);
    });
  });

  group('messaging', () {
    test('a user message crosses the hub', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 5));

      final delivered = participant.waitForUserMessage(
        'phase',
        timeout: const Duration(seconds: 5),
      );
      await coordinator.sendUserMessage('phase', 'start', {'phase': 1});

      final event = await delivered;
      expect(event.messageType, 'phase');
      expect(event.payload['phase'], 1);
    });
  });

  group('data streams', () {
    test('binary samples arrive in order, with values intact', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final producer = await joined('producer', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 5));

      final producerReady = Completer<DataStream>();
      final producerSub = producer.events.streamStart.listen((event) async {
        if (producerReady.isCompleted) return;
        producerReady.complete(await producer.getDataStream(event.streamName));
      });

      final received = <List<double>>[];
      final coordinatorStream = await coordinator.createDataStream(
        DataStreamConfig(
          name: 'TestData',
          channels: 2,
          sampleRate: 50.0,
          dataType: StreamDataType.double64,
          participationMode:
              StreamParticipationMode.sendParticipantsReceiveCoordinator,
        ),
      );
      final inboxSub = coordinatorStream.inbox.listen((message) {
        received.add(message.data.cast<double>().toList());
      });

      await coordinator.startStream('TestData');
      final producerStream = await producerReady.future.timeout(
        const Duration(seconds: 5),
      );

      const sampleCount = 20;
      for (var i = 0; i < sampleCount; i++) {
        await producerStream.sendData([i.toDouble(), i * 1.5]);
      }

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (received.length < sampleCount &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(received, hasLength(sampleCount));
      for (var i = 0; i < sampleCount; i++) {
        // Bit-exact: the binary framing must not round-trip through a double
        // approximation.
        expect(received[i], [i.toDouble(), i * 1.5], reason: 'sample $i');
      }

      await coordinator.stopStream('TestData');
      await inboxSub.cancel();
      await producerSub.cancel();
    });
  });

  group('disconnection', () {
    test('the hub drops a peer when its socket closes', () async {
      final connection = WsConnection(hubUri);
      await connection.connect();
      await connection.announce(
        PeerDescriptor(
          streamName: 'coordination',
          sessionName: 'WsSession',
          nodeId: 'n1',
          nodeUId: 'uid-1',
          nodeRole: 'participant',
          endpointId: 'WsSession/uid-1/coordination',
        ),
      );
      expect(hub.endpointCount, 1);

      await connection.close();

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (hub.endpointCount > 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
        hub.endpointCount,
        0,
        reason: 'a dropped socket must not leave a stale peer registered',
      );
      expect(hub.connectionCount, 0);
    });
  });
}
