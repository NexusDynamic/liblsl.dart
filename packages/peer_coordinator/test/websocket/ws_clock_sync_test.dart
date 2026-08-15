/// End-to-end clock sync over a real WebSocket hub.
///
/// The unit tests in `test/coordination/clock_sync_test.dart` pin the
/// arithmetic with injected timestamps. This pins the *plumbing*: that probes
/// actually go out over the coordination stream, that both roles answer them,
/// that replies carry the four timestamps back, and that the resulting offset
/// reaches both a coordination event and a data sample.
///
/// It also pins the negative case — that LSL and the in-memory transport do not
/// run an estimator at all, because they do not need one.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/in_memory.dart';
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

  // Bursts far faster than liblsl's 2s default, so a test does not spend
  // seconds waiting for an estimate. The shape is identical; only the cadence
  // differs, which is exactly what ClockSyncConfig is exposed for.
  const fastClockSync = ClockSyncConfig(
    timeUpdateInterval: Duration(milliseconds: 400),
    timeProbeCount: 8,
    timeProbeInterval: Duration(milliseconds: 10),
    timeProbeMaxRtt: Duration(milliseconds: 100),
    timeUpdateMinProbes: 6,
  );

  CoordinationConfig configFor({
    required ITransportConfig transportConfig,
    ClockSyncConfig clockSync = fastClockSync,
    int maxNodes = 3,
  }) => CoordinationConfig(
    name: 'clocksync_test',
    sessionConfig: CoordinationSessionConfig(
      name: 'ClockSyncSession',
      maxNodes: maxNodes,
      minNodes: 1,
      heartbeatInterval: const Duration(milliseconds: 100),
      discoveryInterval: const Duration(milliseconds: 50),
      nodeTimeout: const Duration(milliseconds: 800),
      consumeCoordinationStreamAsCoordinator: false,
      clockSyncConfig: clockSync,
    ),
    topologyConfig: HierarchicalTopologyConfig(
      promotionStrategy: PromotionStrategyRandom(),
      maxNodes: maxNodes,
    ),
    streamConfig: CoordinationStreamConfig(name: 'coordination'),
    transportConfig: transportConfig,
  );

  Future<PeerSession> joined(
    String name, {
    required double randomRoll,
    ITransportConfig? transportConfig,
  }) async {
    final session = PeerSession.create(
      configFor(
        transportConfig:
            transportConfig ?? WebSocketTransportConfig(hubUri: hubUri),
      ),
      thisNodeConfig: NodeConfig(
        name: name,
        id: name,
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
        metadata: {PeerMetadataKeys.randomRoll: randomRoll.toString()},
      ),
    );
    sessions.add(session);
    await session.initialize();
    await session.join(const Duration(seconds: 3));
    return session;
  }

  /// Polls until [check] passes or the deadline expires, so the test waits for
  /// as long as a burst actually needs rather than a fixed guess.
  Future<void> waitFor(
    bool Function() check, {
    Duration timeout = const Duration(seconds: 5),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (check()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail(reason ?? 'condition not met within $timeout');
  }

  group('websocket clock sync', () {
    test('both peers estimate each other, one estimator per inlet', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 3));

      final coordOffsets = (coordinator.transport as WebSocketTransport)
          .clockOffsets;
      final partOffsets = (participant.transport as WebSocketTransport)
          .clockOffsets;

      // Each side has an inlet from the other, so each side estimates the
      // other — the coordinator reads from the participant and vice versa.
      await waitFor(
        () =>
            coordOffsets.offsetFor(participant.thisNode.uId) != null &&
            partOffsets.offsetFor(coordinator.thisNode.uId) != null,
        reason: 'both peers should have an offset after a couple of bursts',
      );

      // Nobody probes themselves.
      expect(coordOffsets.offsetFor(coordinator.thisNode.uId), isNull);
      expect(partOffsets.offsetFor(participant.thisNode.uId), isNull);
    });

    test('the two estimates are near-opposite and tightly bounded', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 3));

      final coordOffsets = (coordinator.transport as WebSocketTransport)
          .clockOffsets;
      final partOffsets = (participant.transport as WebSocketTransport)
          .clockOffsets;

      await waitFor(
        () =>
            coordOffsets.offsetFor(participant.thisNode.uId) != null &&
            partOffsets.offsetFor(coordinator.thisNode.uId) != null,
      );

      final a = coordOffsets.estimateFor(participant.thisNode.uId)!;
      final b = partOffsets.estimateFor(coordinator.thisNode.uId)!;

      // A maps B's clock into A's domain; B maps A's into B's. They describe the
      // same difference from opposite ends, so they should sum to ~zero. Any
      // residual is the two measurements' path asymmetry, bounded by their
      // uncertainties.
      final residual = (a.offset + b.offset).abs();
      expect(
        residual,
        lessThan((a.uncertainty + b.uncertainty) / 2 + 0.005),
        reason:
            'offsets $a and $b should be near-opposite; residual '
            '${residual * 1e6}us exceeds the stated bounds',
      );

      // Both processes are on this machine, so loopback RTT is sub-millisecond.
      expect(a.uncertainty, lessThan(0.1));
      expect(b.uncertainty, lessThan(0.1));
      expect(a.uncertainty, greaterThanOrEqualTo(0));
    });

    test('a coordination event reports a real transit time', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 3));

      final partOffsets = (participant.transport as WebSocketTransport)
          .clockOffsets;
      await waitFor(
        () => partOffsets.offsetFor(coordinator.thisNode.uId) != null,
      );

      final delivered = participant.waitForUserMessage(
        'probe',
        timeout: const Duration(seconds: 3),
      );
      await coordinator.sendUserMessage('probe', 'hello', {'n': 1});
      final event = await delivered;

      final timing = event.timing!;
      expect(timing.sourceClock, isNotNull);
      expect(
        timing.clockOffset,
        isNotNull,
        reason: 'the estimator should have filled this in by now',
      );
      expect(timing.uncertainty, isNotNull);

      final transit = timing.transitSeconds;
      expect(transit, isNotNull);
      // Loopback through an in-process hub. Loose bounds: this asserts the
      // arithmetic lands in the right units and the right clock domain, not
      // that the machine is fast. Slightly negative is legitimate — the offset
      // is an estimate with the uncertainty this same timing reports.
      expect(transit!, greaterThan(-0.05));
      expect(transit, lessThan(2.0));
      expect(
        timing.transitUncertaintySeconds,
        closeTo(timing.uncertainty! / 2, 1e-12),
      );
    });

    test('a data sample names its sender and carries the offset', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 3));

      final coordOffsets = (coordinator.transport as WebSocketTransport)
          .clockOffsets;
      await waitFor(
        () => coordOffsets.offsetFor(participant.thisNode.uId) != null,
      );

      final streamConfig = DataStreamConfig(
        name: 'TimingData',
        channels: 2,
        sampleRate: 50.0,
        dataType: StreamDataType.double64,
        participationMode:
            StreamParticipationMode.sendParticipantsReceiveCoordinator,
      );

      final received = Completer<IMessage>();
      final stream = await coordinator.createDataStream(streamConfig);
      final sub = stream.inbox.listen((message) {
        if (!received.isCompleted) received.complete(message);
      });

      final producerReady = Completer<DataStream>();
      final startSub = participant.events.streamStart.listen((event) async {
        if (!producerReady.isCompleted) {
          producerReady.complete(
            await participant.getDataStream(event.streamName),
          );
        }
      });

      await coordinator.startStream('TimingData');
      final producer = await producerReady.future.timeout(
        const Duration(seconds: 5),
      );

      final pump = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (producer.started) producer.sendData([1.0, 2.0]);
      });

      final message = await received.future.timeout(const Duration(seconds: 5));
      pump.cancel();
      await sub.cancel();
      await startSub.cancel();

      final timing = message.timing!;
      // The slot -> nodeUId map is what makes this a name rather than a number.
      expect(
        timing.sourceId,
        participant.thisNode.uId,
        reason: 'a sample should identify its producing peer, not a hub slot',
      );
      expect(
        timing.clockOffset,
        isNotNull,
        reason: 'the data path should reuse the coordination-stream estimate',
      );
      expect(timing.transitSeconds, isNotNull);
      expect(timing.transitSeconds!, greaterThan(-0.05));
      expect(timing.transitSeconds!, lessThan(2.0));

      await coordinator.stopStream('TimingData');
    });

    test('a departed peer forgets its offset rather than going stale', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 3));

      final coordOffsets = (coordinator.transport as WebSocketTransport)
          .clockOffsets;
      final participantUId = participant.thisNode.uId;
      await waitFor(() => coordOffsets.offsetFor(participantUId) != null);

      await participant.leave();
      await waitFor(
        () => coordOffsets.offsetFor(participantUId) == null,
        reason: 'the offset should be dropped when the peer leaves',
      );
    });
  });

  group('transports that do not need an estimator', () {
    test('in-memory keeps a known-zero offset and estimates nothing', () async {
      final bus = InMemoryBus();
      addTearDown(bus.dispose);

      final coordinator = await joined(
        'mem-coord',
        randomRoll: 0.1,
        transportConfig: InMemoryTransportConfig(bus: bus),
      );
      final participant = await joined(
        'mem-participant',
        randomRoll: 0.9,
        transportConfig: InMemoryTransportConfig(bus: bus),
      );
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 3));

      // No table at all: the offset is structurally zero, not estimated.
      expect(participant.transport.clockOffsets, isNull);
      expect(coordinator.transport.clockOffsets, isNull);

      final delivered = participant.waitForUserMessage(
        'probe',
        timeout: const Duration(seconds: 3),
      );
      await coordinator.sendUserMessage('probe', 'hello', {});
      final event = await delivered;

      expect(event.timing!.clockOffset, 0.0);
      expect(event.timing!.transitSeconds, isNotNull);
    });
  });
}
