/// Data-stream inlets have to come back when a node rejoins.
///
/// A node that departs has its data-stream inlets released
/// (`PeerSession._setupDepartureHandler`), and a participant losing its
/// coordinator releases them all at once: `_teardownRole` clears the topology,
/// which emits a departure for the coordinator itself. Nothing re-created them
/// on rejoin — only the coordination inlet was re-added — so the stream stayed
/// silent until the application destroyed and re-created it.
///
/// Field failure, 2026-09-11: three iPads were evicted mid-trial after a
/// transient stall, rejoined within seconds over a healthy link, and never
/// received another PhysicsState sample. The coordinator had likewise dropped
/// their GameData inlets, so their paddle actions went nowhere either.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:peer_coordinator/in_memory.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryBus bus;
  late List<PeerSession> sessions;

  const sessionName = 'RejoinInletSession';
  const coordinationStreamName = 'coordination';
  const nodeTimeout = Duration(milliseconds: 400);

  setUp(() {
    bus = InMemoryBus();
    sessions = [];
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      try {
        await session.leave();
      } catch (_) {
        // Teardown must not mask the assertion that failed.
      }
      try {
        await session.dispose();
      } catch (_) {}
    }
    sessions = [];
    bus.dispose();
  });

  CoordinationConfig configFor(CoordinatorLossPolicy policy) =>
      CoordinationConfig(
        name: 'rejoin_inlet_test',
        sessionConfig: CoordinationSessionConfig(
          name: sessionName,
          maxNodes: 3,
          minNodes: 1,
          heartbeatInterval: const Duration(milliseconds: 50),
          discoveryInterval: const Duration(milliseconds: 25),
          nodeTimeout: nodeTimeout,
          consumeCoordinationStreamAsCoordinator: false,
          coordinatorLossPolicy: policy,
        ),
        topologyConfig: HierarchicalTopologyConfig(
          promotionStrategy: PromotionStrategyRandom(),
          maxNodes: 3,
        ),
        streamConfig: CoordinationStreamConfig(name: coordinationStreamName),
        transportConfig: InMemoryTransportConfig(bus: bus),
      );

  Future<PeerSession> joined(
    String name, {
    required double randomRoll,
    CoordinatorLossPolicy policy = CoordinatorLossPolicy.endSession,
  }) async {
    final session = PeerSession.create(
      configFor(policy),
      thisNodeConfig: NodeConfig(
        name: name,
        id: name,
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
        metadata: {PeerMetadataKeys.randomRoll: randomRoll.toString()},
      ),
    );
    sessions.add(session);
    await session.initialize();
    await session.join(const Duration(milliseconds: 500));
    return session;
  }

  DataStreamConfig dataConfig(String name, StreamParticipationMode mode) =>
      DataStreamConfig(
        name: name,
        channels: 2,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
        participationMode: mode,
      );

  /// Evicts [participant] with a one-directional coordination stall, restores
  /// the link, and waits for the rejoin — the 2026-09-11 sequence.
  Future<void> evictAndRejoin(
    PeerSession coordinator,
    PeerSession participant,
  ) async {
    final rejoined = participant.events.sessionRejoined.first.timeout(
      const Duration(seconds: 5),
    );
    final ended = participant.events.sessionEnded.first.timeout(
      const Duration(seconds: 3),
    );
    final producer =
        '$sessionName/${participant.thisNode.uId}/$coordinationStreamName';
    final subscriber =
        '$sessionName/${coordinator.thisNode.uId}/$coordinationStreamName';

    bus.routing.unsubscribe(
      streamName: coordinationStreamName,
      producerEndpointId: producer,
      subscriberEndpointId: subscriber,
    );
    expect((await ended).reason, SessionEndReason.evicted);

    bus.routing.subscribe(
      streamName: coordinationStreamName,
      producerEndpointId: producer,
      subscriberEndpointId: subscriber,
    );
    await rejoined;
    await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 3));
  }

  /// Completes once [count] has moved past [from], or fails after [timeout].
  Future<void> expectDeliveryResumes(
    int Function() count, {
    required int from,
    required String reason,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (count() <= from && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(count(), greaterThan(from), reason: reason);
  }

  test(
    'a participant receives coordinator data again after rejoining',
    () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined(
        'p1',
        randomRoll: 0.9,
        policy: CoordinatorLossPolicy.rejoin,
      );
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      const name = 'Physics';
      final outlet = await coordinator.createDataStream(
        dataConfig(name, StreamParticipationMode.coordinatorOnly),
      );
      await coordinator.startStream(name);

      final inlet = await participant.getDataStream(name);
      var received = 0;
      final inboxSub = inlet.inbox.listen((_) => received++);
      addTearDown(inboxSub.cancel);

      final sender = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (outlet.started) outlet.sendData([1.0, 2.0]);
      });
      addTearDown(sender.cancel);

      await expectDeliveryResumes(
        () => received,
        from: 0,
        reason: 'samples should flow before any fault',
      );

      await evictAndRejoin(coordinator, participant);

      await expectDeliveryResumes(
        () => received,
        from: received,
        reason:
            'the rejoined participant must get its data-stream inlet to the '
            'coordinator back, not only the coordination inlet',
      );
    },
  );

  test(
    'the coordinator receives a participant\'s data again after it rejoins',
    () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined(
        'p1',
        randomRoll: 0.9,
        policy: CoordinatorLossPolicy.rejoin,
      );
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      const name = 'Actions';
      final startSub = participant.events.streamStart.listen((event) async {
        if (event.streamName != name) return;
        final stream = await participant.getDataStream(name);
        if (!stream.started) await stream.start();
      });
      addTearDown(startSub.cancel);

      final inlet = await coordinator.createDataStream(
        dataConfig(name, StreamParticipationMode.sendParticipantsReceiveCoordinator),
      );
      var received = 0;
      final inboxSub = inlet.inbox.listen((_) => received++);
      addTearDown(inboxSub.cancel);
      await coordinator.startStream(name);

      final outlet = await participant.getDataStream(name);
      final sender = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (outlet.started) outlet.sendData([3.0, 4.0]);
      });
      addTearDown(sender.cancel);

      await expectDeliveryResumes(
        () => received,
        from: 0,
        reason: 'samples should flow before any fault',
      );

      await evictAndRejoin(coordinator, participant);

      await expectDeliveryResumes(
        () => received,
        from: received,
        reason:
            'the coordinator must re-create its inlet for a rejoined '
            'participant, or that participant\'s input is silently lost',
      );
    },
  );
}
