/// Drives whole coordination sessions over the in-memory transport.
///
/// This is the payoff of the transport extraction: election, join, heartbeat,
/// the stream lifecycle and the data path all run here with no sockets, no
/// native code and no timing luck — and the code under test is exactly the
/// code the LSL transport runs, because everything transport-neutral is
/// shared.
///
/// It is also the proof that the abstraction is genuine rather than
/// LSL-shaped: anything the coordination layer needs that could not be
/// expressed against a plain in-process bus would be coupling that leaked.
library;

import 'dart:async';

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/memory.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryBus bus;
  late List<PeerSession> sessions;

  setUp(() {
    bus = InMemoryBus();
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
    bus.dispose();
  });

  CoordinationConfig configFor({int maxNodes = 3}) => CoordinationConfig(
    name: 'memory_test',
    sessionConfig: CoordinationSessionConfig(
      name: 'MemorySession',
      maxNodes: maxNodes,
      minNodes: 1,
      heartbeatInterval: const Duration(milliseconds: 50),
      discoveryInterval: const Duration(milliseconds: 25),
      nodeTimeout: const Duration(milliseconds: 400),
      consumeCoordinationStreamAsCoordinator: false,
    ),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: maxNodes,
    ),
    streamConfig: CoordinationStreamConfig(name: 'coordination'),
    transportConfig: InMemoryTransportConfig(bus: bus),
  );

  /// Lower roll wins the election.
  PeerSession makeSession(
    String name, {
    required double randomRoll,
    int maxNodes = 3,
  }) {
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
    return session;
  }

  Future<PeerSession> joined(
    String name, {
    required double randomRoll,
    int maxNodes = 3,
  }) async {
    final session = makeSession(
      name,
      randomRoll: randomRoll,
      maxNodes: maxNodes,
    );
    await session.initialize();
    await session.join(const Duration(milliseconds: 500));
    return session;
  }

  DataStreamConfig dataConfig({
    StreamParticipationMode mode =
        StreamParticipationMode.sendParticipantsReceiveCoordinator,
  }) => DataStreamConfig(
    name: 'TestData',
    channels: 2,
    sampleRate: 50.0,
    dataType: StreamDataType.double64,
    participationMode: mode,
  );

  group('election', () {
    test('a lone node becomes coordinator', () async {
      final only = await joined('solo', randomRoll: 0.5);
      expect(only.isCoordinator, isTrue);
      expect(
        only.connectedNodes.map((n) => n.uId),
        contains(only.thisNode.uId),
      );
    });

    test('two nodes agree on exactly one coordinator', () async {
      final first = await joined('first', randomRoll: 0.1);
      expect(first.isCoordinator, isTrue);

      final second = await joined('second', randomRoll: 0.9);
      expect(second.isCoordinator, isFalse);

      await first.waitForMinNodes(2, timeout: const Duration(seconds: 2));
      expect(first.connectedNodes, hasLength(2));
      expect(first.connectedParticipantNodes, hasLength(1));
      expect(second.coordinatorUId, first.thisNode.uId);
    });

    test('three nodes converge on one coordinator', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      await joined('p1', randomRoll: 0.5);
      await joined('p2', randomRoll: 0.9);

      await coordinator.waitForMinNodes(3, timeout: const Duration(seconds: 3));
      expect(coordinator.isCoordinator, isTrue);
      expect(
        sessions.where((s) => s.isCoordinator),
        hasLength(1),
        reason: 'exactly one node may hold the coordinator role',
      );
      expect(coordinator.connectedNodes, hasLength(3));
    });

    test('sessions on one bus have distinct uIds', () async {
      // Regression test: session, data-stream and coordination-stream classes
      // all used a mixin that cached uId in a static Map<Type, String>, so
      // every instance in a process shared one. Harmless across processes,
      // fatal here.
      final a = makeSession('a', randomRoll: 0.1);
      final b = makeSession('b', randomRoll: 0.9);
      expect(a.uId, isNot(b.uId));
      expect(a.thisNode.uId, isNot(b.thisNode.uId));
    });
  });

  group('membership', () {
    test('a node past maxNodes is rejected', () async {
      final coordinator = await joined('coord', randomRoll: 0.1, maxNodes: 2);
      await joined('accepted', randomRoll: 0.5, maxNodes: 2);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final rejections = <NodeJoinRejectedEvent>[];
      final sub = coordinator.events.nodeJoinRejected.listen(rejections.add);

      final surplus = makeSession('surplus', randomRoll: 0.9, maxNodes: 2);
      await surplus.initialize();
      try {
        await surplus.join(const Duration(milliseconds: 500));
      } catch (_) {
        // A rejected node cannot currently distinguish rejection from a
        // timeout; the coordinator's view is the contract. See the LSL
        // characterisation suite for the detail.
      }

      expect(rejections, isNotEmpty);
      expect(rejections.first.reason, 'Maximum nodes reached');
      expect(rejections.first.rejectedNodeUId, surplus.thisNode.uId);
      expect(
        coordinator.connectedNodes.map((n) => n.uId),
        isNot(contains(surplus.thisNode.uId)),
      );
      expect(coordinator.connectedNodes, hasLength(2));
      await sub.cancel();
    });

    test('a graceful leave removes the node', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final leaver = await joined('leaver', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final left = Completer<NodeLeftEvent>();
      final sub = coordinator.events.nodeLeft.listen((e) {
        if (!left.isCompleted) left.complete(e);
      });

      await leaver.leave();

      final event = await left.future.timeout(const Duration(seconds: 2));
      expect(event.node.uId, leaver.thisNode.uId);
      expect(coordinator.connectedNodes, hasLength(1));
      await sub.cancel();
    });

    test('a silent node is timed out', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final dropout = await joined('dropout', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final left = Completer<NodeLeftEvent>();
      final sub = coordinator.events.nodeLeft.listen((e) {
        if (!left.isCompleted) left.complete(e);
      });

      // Yank the transport without announcing: the coordinator should notice
      // via the heartbeat timeout rather than a leave message.
      bus.disconnect(
        PeerDescriptor.forNode(
          node: dropout.thisNode,
          streamName: 'coordination',
          sessionName: 'MemorySession',
        ).endpointId,
      );

      final event = await left.future.timeout(const Duration(seconds: 3));
      expect(event.node.uId, dropout.thisNode.uId);
      await sub.cancel();
    });
  });

  group('messaging', () {
    test('a user message reaches the participant', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final delivered = participant.waitForUserMessage(
        'phase',
        timeout: const Duration(seconds: 2),
      );
      await coordinator.sendUserMessage('phase', 'start phase 1', {'phase': 1});

      final event = await delivered;
      expect(event.messageType, 'phase');
      expect(event.description, 'start phase 1');
      expect(event.payload['phase'], 1);
    });

    test('a config update reaches the participant', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final updates = <ConfigUpdateEvent>[];
      final sub = participant.events.configUpdates.listen(updates.add);

      await coordinator.updateConfig({'rate': 60});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(updates, isNotEmpty);
      expect(updates.first.config['rate'], 60);
      await sub.cancel();
    });
  });

  group('data streams', () {
    test('samples flow from participant to coordinator, in order', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final producer = await joined('producer', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final producerReady = Completer<DataStream>();
      final producerSub = producer.events.streamStart.listen((event) async {
        if (producerReady.isCompleted) return;
        producerReady.complete(await producer.getDataStream(event.streamName));
      });

      final received = <List<double>>[];
      final coordinatorStream = await coordinator.createDataStream(
        dataConfig(),
      );
      final inboxSub = coordinatorStream.inbox.listen((message) {
        received.add(message.data.cast<double>().toList());
      });

      await coordinator.startStream('TestData');
      final producerStream = await producerReady.future.timeout(
        const Duration(seconds: 3),
      );

      const sampleCount = 25;
      for (var i = 0; i < sampleCount; i++) {
        await producerStream.sendData([i.toDouble(), i * 2.0]);
      }

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (received.length < sampleCount &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(received, hasLength(sampleCount), reason: 'no loss expected');
      for (var i = 0; i < sampleCount; i++) {
        expect(received[i], [i.toDouble(), i * 2.0], reason: 'sample $i');
      }

      await coordinator.stopStream('TestData');
      await inboxSub.cancel();
      await producerSub.cancel();
    });

    test('a paused stream delivers nothing until resumed', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final producer = await joined('producer', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final producerReady = Completer<DataStream>();
      final producerSub = producer.events.streamStart.listen((event) async {
        if (producerReady.isCompleted) return;
        producerReady.complete(await producer.getDataStream(event.streamName));
      });

      var received = 0;
      final coordinatorStream = await coordinator.createDataStream(
        dataConfig(),
      );
      final inboxSub = coordinatorStream.inbox.listen((_) => received++);

      await coordinator.startStream('TestData');
      final producerStream = await producerReady.future.timeout(
        const Duration(seconds: 3),
      );

      await coordinator.pauseStream('TestData');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final beforePause = received;

      for (var i = 0; i < 5; i++) {
        try {
          await producerStream.sendData([i.toDouble(), 0.0]);
        } catch (_) {
          // A paused producer may refuse outright; either way nothing should
          // reach the coordinator.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(received, beforePause, reason: 'nothing may arrive while paused');

      await coordinator.resumeStream('TestData', flushBeforeResume: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await producerStream.sendData([99.0, 99.0]);

      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (received == beforePause && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        received,
        greaterThan(beforePause),
        reason: 'delivery must resume',
      );

      await inboxSub.cancel();
      await producerSub.cancel();
    });
  });

  group('teardown', () {
    test('a full lifecycle disposes without throwing', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      await expectLater(participant.leave(), completes);
      await expectLater(participant.dispose(), completes);
      await expectLater(coordinator.leave(), completes);
      await expectLater(coordinator.dispose(), completes);

      sessions.clear();
    });
  });
}
