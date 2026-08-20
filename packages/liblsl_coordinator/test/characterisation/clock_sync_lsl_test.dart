/// Clock-offset estimates are reported on their own cadence, not only when a
/// message happens to arrive.
///
/// `MessageTiming` can describe an estimate only if it was attached to a sample
/// that was actually delivered, so on a quiet stream the offset series has
/// holes and drift between the readings has to be guessed. `clockSyncs` closes
/// that: it emits every estimate the inlet worker makes, whether or not any
/// data moved, and carries the two things `MessageTiming` structurally cannot —
/// the peer's own clock at the moment of measurement, which is what makes a
/// series fittable, and the clock-reset flag, which says where a fit must stop.
///
/// See `test/support/lsl_harness.dart` for why every node has to live in one
/// process under one process-global LSL config.
@Tags(['lsl', 'integration'])
library;

import 'dart:async';

import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:test/test.dart';

import '../support/lsl_harness.dart';

void main() {
  useLoopbackLsl();

  late List<LSLCoordinationSession> sessions;
  late String sessionName;

  setUp(() {
    sessions = [];
    sessionName = uniqueSessionName('ClockSyncTest');
  });

  tearDown(() async {
    for (final session in sessions.reversed) {
      try {
        await session.leave();
      } catch (_) {}
      try {
        await session.dispose();
      } catch (_) {}
    }
    sessions = [];
  });

  Future<LSLCoordinationSession> joined(
    String name, {
    required double randomRoll,
  }) async {
    final session = LSLCoordinationSession(
      testCoordinationConfig(sessionName: sessionName, maxNodes: 2),
      thisNodeConfig: testNodeConfig(name: name, randomRoll: randomRoll),
    );
    sessions.add(session);
    await session.initialize();
    await session.join(const Duration(seconds: 3));
    return session;
  }

  test('the coordination stream reports estimates without any traffic', () async {
    final coordinator = await joined('coord', randomRoll: 0.1);
    final participant = await joined('participant', randomRoll: 0.9);
    await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 5));

    // Nothing is sent for the rest of this test. That is the point: an estimate
    // must arrive anyway, because it is the clocks being measured, not the
    // traffic.
    final sample = await participant.coordinationClockSyncs.first.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StateError(
        'no clock-sync estimate arrived; a quiet stream must still report one',
      ),
    );

    // Both nodes share a process and therefore an LSL clock, so the offset is
    // ~0 — but it must be *present*: null means "no estimate yet", which is a
    // different statement from a known zero.
    expect(sample.offset, isNotNull);
    expect(sample.offset!.abs(), lessThan(0.1));

    // liblsl's own error bound, from the same lsl_time_correction_ex round trip
    // as the offset. Full RTT, so `bound` is half of it.
    expect(sample.uncertainty, isNotNull);
    expect(sample.uncertainty!, greaterThanOrEqualTo(0));
    expect(sample.uncertainty!, lessThan(1.0));
    expect(sample.bound, closeTo(sample.uncertainty! / 2, 1e-12));

    // The peer's clock at measurement time. `MessageTiming` discards this, and
    // without it a sequence of offsets says how far apart the clocks are but
    // not how that gap is changing — which is the entire drift term.
    expect(sample.remoteTime, isNotNull);
    expect(sample.remoteTime!, greaterThan(0));

    // The local clock at the same instant, in the local domain.
    expect(sample.receivedClock, greaterThan(0));

    // Nothing has restarted mid-test, so a true here would mean the flag is
    // being misread rather than that a reset happened.
    expect(sample.clockReset, isFalse);

    // Identifies which peer this estimate is for; without it, a node with
    // several inlets cannot tell the series apart.
    expect(sample.sourceId, isNotNull);
    expect(sample.sourceId, contains(coordinator.thisNode.uId));
  });

  test(
    'estimates keep arriving, so drift is a series and not a reading',
    () async {
      final coordinator = await joined('coord', randomRoll: 0.1);
      final participant = await joined('participant', randomRoll: 0.9);
      await coordinator.waitForMinNodes(2, timeout: const Duration(seconds: 5));

      // The refresh interval is 5 s, so two estimates need a little over that.
      final samples = await participant.coordinationClockSyncs
          .take(2)
          .toList()
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                throw StateError('estimates stopped after the first'),
          );

      expect(samples, hasLength(2));
      expect(
        samples[1].receivedClock,
        greaterThan(samples[0].receivedClock),
        reason:
            'each estimate is a fresh measurement, not a cached one replayed',
      );
      expect(
        samples[1].remoteTime,
        greaterThan(samples[0].remoteTime!),
        reason:
            'the remote clock advances between probes; (remoteTime, offset) '
            'pairs are what a drift fit consumes',
      );
    },
  );
}
