/// Ordering guarantees around `createDataStream` and `startStream`.
///
/// A `coordinatorOnly` stream used to complete creation without waiting for
/// anyone: `_waitForParticipantStreamsReady` was only consulted for
/// *producers*, and such a stream has none. The coordinator therefore returned
/// from `createDataStream` and broadcast `startStream` milliseconds later,
/// while participants needed the best part of a second to resolve the outlet
/// and build an inlet. The start command overtook its own create, and the
/// participant was left with a stream the coordinator believed was running.
///
/// The same window broke plain lookups: `_streamLock` only covers registration
/// in `_dataStreams`, so anything calling `getDataStream` during the unlocked
/// wiring that follows was told the stream did not exist.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:peer_coordinator/in_memory.dart';
import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryBus bus;
  late List<PeerSession> sessions;
  var runCounter = 0;
  late String runId;

  setUp(() {
    bus = InMemoryBus();
    sessions = [];
    runId = '${DateTime.now().microsecondsSinceEpoch}-${runCounter++}';
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      try {
        await session.leave();
      } catch (_) {
        // Teardown must not mask the assertion that failed.
      }
      await session.dispose();
    }
    sessions = [];
    bus.dispose();
  });

  CoordinationConfig configFor(int index) => CoordinationConfig(
    name: 'stream_race_test',
    sessionConfig: CoordinationSessionConfig(
      name: 'StreamRaceSession-$runId',
      maxNodes: 2,
      minNodes: 1,
      heartbeatInterval: const Duration(milliseconds: 100),
      discoveryInterval: const Duration(milliseconds: 50),
      nodeTimeout: const Duration(milliseconds: 800),
      consumeCoordinationStreamAsCoordinator: false,
    ),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: 2,
    ),
    streamConfig: CoordinationStreamConfig(name: 'coordination-$runId'),
    transportConfig: InMemoryTransportConfig(bus: bus),
  );

  /// One coordinator and one participant, joined and mutually aware.
  Future<({PeerSession coordinator, PeerSession participant})>
  buildSession() async {
    const labels = ['coordinator', 'participant'];
    const rolls = [0.1, 0.9];

    for (var i = 0; i < labels.length; i++) {
      final session = PeerSession.create(
        configFor(i),
        thisNodeConfig: NodeConfig(
          name: labels[i],
          id: '${labels[i]}-$runId',
          capabilities: {
            NodeCapability.coordinator,
            NodeCapability.participant,
          },
          metadata: {PeerMetadataKeys.randomRoll: rolls[i].toString()},
        ),
      );
      sessions.add(session);
      await session.initialize();
      await session.join(const Duration(milliseconds: 500));
    }

    await sessions.first.waitForMinNodes(
      2,
      timeout: const Duration(seconds: 10),
    );
    expect(sessions.first.isCoordinator, isTrue);
    expect(sessions.last.isCoordinator, isFalse);
    return (coordinator: sessions.first, participant: sessions.last);
  }

  DataStreamConfig configNamed(String name, StreamParticipationMode mode) =>
      DataStreamConfig(
        name: name,
        channels: 2,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
        participationMode: mode,
      );

  test(
    'a coordinatorOnly create does not complete until consumers have it',
    () async {
      final nodes = await buildSession();
      final name = 'CoordinatorOnly-$runId';

      await nodes.coordinator.createDataStream(
        configNamed(name, StreamParticipationMode.coordinatorOnly),
      );

      // No polling, no settle: returning from createDataStream is the whole
      // guarantee under test. Without the consumer wait this throws
      // ArgumentError, because the participant is still building its inlet.
      await expectLater(nodes.participant.getDataStream(name), completes);
    },
  );

  test('an immediate startStream reaches the consumer', () async {
    final nodes = await buildSession();
    final name = 'ImmediateStart-$runId';

    await nodes.coordinator.createDataStream(
      configNamed(name, StreamParticipationMode.coordinatorOnly),
    );
    // Exactly what NetworkCoordinator._startOrResumeStreams does next, with
    // nothing in between — the 3 ms gap that broke every joint trial.
    await nodes.coordinator.startStream(name);

    final stream = await nodes.participant.getDataStream(name);
    await _until(() => stream.started);
    expect(
      stream.started,
      isTrue,
      reason: 'a start command must not be dropped for a stream mid-creation',
    );
  });

  test('getDataStream queues behind an in-flight create', () async {
    final nodes = await buildSession();
    final name = 'InFlight-$runId';

    // Deliberately not awaited: the lookup below lands inside the unlocked
    // outlet/inlet wiring, which is the window that used to report
    // 'Stream not found' for a stream that was very much being created.
    final creating = nodes.coordinator.createDataStream(
      configNamed(name, StreamParticipationMode.allNodes),
    );

    await expectLater(nodes.coordinator.getDataStream(name), completes);
    await creating;
  });

  test('getDataStream still throws for a stream nobody is creating', () async {
    final nodes = await buildSession();

    await expectLater(
      nodes.coordinator.getDataStream('NeverCreated-$runId'),
      throwsA(isA<ArgumentError>()),
    );
  });
}

/// Polls [condition] up to [timeout]. Only for assertions about a broadcast
/// arriving, never for ones about a future having completed.
Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
