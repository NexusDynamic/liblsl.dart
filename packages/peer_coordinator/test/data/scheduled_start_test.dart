/// `startStream(startAt:)`: every node starts the stream at the scheduled
/// instant, and whatever supersedes a scheduled start cancels it.
///
/// The in-memory transport's nodes share one clock, so the offset between
/// them is a known zero and the instant can be checked exactly.
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
    name: 'scheduled_start_test',
    sessionConfig: CoordinationSessionConfig(
      name: 'ScheduledStartSession-$runId',
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

  Future<void> createStream(PeerSession coordinator, String name) => coordinator
      .createDataStream(configNamed(name, StreamParticipationMode.allNodes));

  /// The clock at which [stream] is first seen started, polled every
  /// millisecond.
  Future<double> startedAt(DataStream stream) async {
    while (!stream.started) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return PeerClock.now();
  }

  test('the start command carries the time on the sender\'s clock', () {
    final startAt = DateTime.utc(2026, 10, 8, 12);
    final message = StartStreamMessage(
      fromNodeUId: 'coord',
      streamName: 'Data',
      streamConfig: configNamed('Data', StreamParticipationMode.allNodes),
      startAt: startAt,
      startAtClock: 1234.5,
    );
    final copy = StartStreamMessage.fromMap(message.toMap());
    expect(copy.startAt, startAt);
    expect(copy.startAtClock, 1234.5);

    final unscheduled = StartStreamMessage.fromMap(
      (message.toMap()
        ..remove('startAt')
        ..remove('startAtClock')),
    );
    expect(unscheduled.startAt, isNull);
    expect(unscheduled.startAtClock, isNull);
  });

  test('every node starts at the scheduled time', () async {
    final nodes = await buildSession();
    await createStream(nodes.coordinator, 'Scheduled');
    final onCoordinator = await nodes.coordinator.getDataStream('Scheduled');
    final onParticipant = await nodes.participant.getDataStream('Scheduled');

    const lead = Duration(milliseconds: 400);
    final target = PeerClock.now() + lead.inMicroseconds / 1e6;
    final starting = nodes.coordinator.startStream(
      'Scheduled',
      startAt: DateTime.now().add(lead),
    );

    await Future<void>.delayed(lead ~/ 2);
    expect(onCoordinator.started, isFalse);
    expect(onParticipant.started, isFalse);

    final times = await Future.wait([
      startedAt(onCoordinator),
      startedAt(onParticipant),
    ]);
    await starting;
    for (final time in times) {
      // Not before the target (less the millisecond between the two clock
      // readings that define it), and within a few timer ticks after it.
      expect(time - target, greaterThan(-0.002));
      expect(time - target, lessThan(0.05));
    }
  });

  test('a time already past starts at once', () async {
    final nodes = await buildSession();
    await createStream(nodes.coordinator, 'Past');
    final onParticipant = await nodes.participant.getDataStream('Past');

    await nodes.coordinator.startStream(
      'Past',
      startAt: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    await startedAt(onParticipant).timeout(const Duration(seconds: 1));
    expect((await nodes.coordinator.getDataStream('Past')).started, isTrue);
  });

  test('stopping before the scheduled time cancels the start', () async {
    final nodes = await buildSession();
    await createStream(nodes.coordinator, 'Cancelled');
    final onCoordinator = await nodes.coordinator.getDataStream('Cancelled');
    final onParticipant = await nodes.participant.getDataStream('Cancelled');

    const lead = Duration(milliseconds: 300);
    final starting = nodes.coordinator.startStream(
      'Cancelled',
      startAt: DateTime.now().add(lead),
    );
    await Future<void>.delayed(lead ~/ 3);
    await nodes.coordinator.stopStream('Cancelled');
    await starting;
    await Future<void>.delayed(lead);

    expect(onCoordinator.started, isFalse);
    expect(onParticipant.started, isFalse);
  });
}
