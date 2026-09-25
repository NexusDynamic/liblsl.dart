/// Coordination traffic must be measurable, not just data samples.
///
/// A coordination message crosses the same network as a data sample; the only
/// difference is how often. Characterising a session's latency for a user
/// therefore means timing both, and for a long time it meant timing neither on
/// the control path: the transport measured the trip and the controller threw
/// the measurement away when it decoded the JSON.
///
/// These tests run over the in-memory transport, where both "peers" share one
/// process and therefore one [PeerClock]. That makes the clock offset a known
/// zero and the transit time exact, so the plumbing can be asserted without a
/// socket, native code, or timing luck.
library;

import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:peer_coordinator/in_memory.dart';
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
    name: 'timing_test',
    sessionConfig: CoordinationSessionConfig(
      name: 'TimingSession',
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

  Future<PeerSession> joined(String name, {required double randomRoll}) async {
    final session = PeerSession.create(
      configFor(),
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

  group('MessageTiming', () {
    test('transitSeconds is null when the clock offset is unknown', () {
      final timing = MessageTiming(sourceClock: 100.0, receivedClock: 100.5);
      expect(timing.clockOffset, isNull);
      expect(timing.sourceClockLocal, isNull);
      // The honest answer, rather than 0.5s of two unrelated clocks' difference.
      expect(timing.transitSeconds, isNull);
      expect(timing.transitMicros, isNull);
    });

    test('transitSeconds is null when the sender clock is unknown', () {
      final timing = MessageTiming(clockOffset: 0.0, receivedClock: 100.5);
      expect(timing.transitSeconds, isNull);
    });

    test('a known offset maps the sender clock into the local domain', () {
      // Sender's clock reads 100.0; it runs 2s behind ours, so locally that
      // instant was 102.0, and we saw the message at 102.25 — 250ms in transit.
      final timing = MessageTiming(
        sourceClock: 100.0,
        clockOffset: 2.0,
        receivedClock: 102.25,
      );
      expect(timing.sourceClockLocal, closeTo(102.0, 1e-9));
      expect(timing.transitSeconds, closeTo(0.25, 1e-9));
      expect(timing.transitMicros, 250000);
    });

    test('a zero offset is distinct from an unknown one', () {
      final known = MessageTiming(
        sourceClock: 10.0,
        clockOffset: 0.0,
        receivedClock: 10.5,
      );
      final unknown = MessageTiming(sourceClock: 10.0, receivedClock: 10.5);
      expect(known.transitSeconds, closeTo(0.5, 1e-9));
      expect(unknown.transitSeconds, isNull);
    });
  });

  group('PeerClock', () {
    test('is monotonic', () {
      final first = PeerClock.now();
      final second = PeerClock.now();
      expect(second, greaterThanOrEqualTo(first));
      expect(first, greaterThanOrEqualTo(0));
    });

    test('nowMicros agrees with now', () {
      final micros = PeerClock.nowMicros();
      final seconds = PeerClock.now();
      expect(seconds, greaterThanOrEqualTo(micros / 1e6));
    });
  });

  group('coordination events carry timing', () {
    test('a user message arrives with a measurable transit time', () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 2));

      final delivered = participant.waitForUserMessage(
        'phase',
        timeout: const Duration(seconds: 2),
      );
      await coordinator.sendUserMessage('phase', 'start phase 1', {'phase': 1});
      final event = await delivered;

      final timing = event.timing;
      expect(
        timing,
        isNotNull,
        reason: 'coordination events must be timeable, not only data samples',
      );
      expect(timing!.sourceClock, isNotNull);
      // Same process, so both ends read the same PeerClock.
      expect(timing.clockOffset, 0.0);
      expect(timing.sourceClockLocal, timing.sourceClock);

      final transit = timing.transitSeconds;
      expect(transit, isNotNull);
      expect(transit!, greaterThanOrEqualTo(0));
      // Generous: this is asserting the arithmetic is in seconds and the two
      // readings come from the same clock, not benchmarking the bus.
      expect(transit, lessThan(2.0));
      expect(timing.transitMicros, (transit * 1e6).round());
    });

    test(
      'the sender clock is stamped at transmit, not at construction',
      () async {
        final coordinator = await joined('coord', randomRoll: 0.1);
        final participant = await joined('participant', randomRoll: 0.9);
        await coordinator.waitForMinNodes(
          2,
          timeout: const Duration(seconds: 2),
        );

        final before = PeerClock.now();
        final delivered = participant.waitForUserMessage(
          'phase',
          timeout: const Duration(seconds: 2),
        );
        await coordinator.sendUserMessage('phase', 'go', {});
        final event = await delivered;
        final after = PeerClock.now();

        final sourceClock = event.timing!.sourceClock!;
        expect(sourceClock, greaterThanOrEqualTo(before));
        expect(sourceClock, lessThanOrEqualTo(after));
      },
    );

    test('locally generated events have no transit to report', () async {
      final coordinator = await joined('solo', randomRoll: 0.5);
      expect(coordinator.isCoordinator, isTrue);

      // A phase change originates here; there is no wire to characterise, and
      // reporting a transit time for one would be a fabrication.
      final phases = <PhaseChangedEvent>[];
      final sub = coordinator.events.phaseChanges.listen(phases.add);
      await coordinator.sendUserMessage('noop', 'noop', {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      for (final phase in phases) {
        expect(phase.timing, isNull);
      }
    });
  });
}
