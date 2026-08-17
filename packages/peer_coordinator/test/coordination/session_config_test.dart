/// Value semantics for [CoordinationSessionConfig].
library;

import 'package:peer_coordinator/peer_coordinator.dart';
import 'package:test/test.dart';

void main() {
  group('identity', () {
    test('hashCode and == terminate', () {
      // Regression test. `id` is `'coordination-$hashCode'` and `hashCode` used to
      // hash `id`, so the two were mutually recursive: any call to either
      // overflowed the stack. Nothing in the package called them, which is why it
      // went unnoticed — but a config in a Set or a Map key would have crashed.
      final config = CoordinationSessionConfig(name: 'S');
      expect(config.hashCode, isA<int>());
      expect(config.id, startsWith('coordination-'));
      expect(config == config, isTrue);
    });

    test('configs differing only in policy are not equal', () {
      final ends = CoordinationSessionConfig(name: 'S');
      final reelects = CoordinationSessionConfig(
        name: 'S',
        coordinatorLossPolicy: CoordinatorLossPolicy.reelect,
      );
      expect(ends == reelects, isFalse);
      expect({ends, reelects}, hasLength(2));
    });

    test('identical field sets are equal and hash alike', () {
      final a = CoordinationSessionConfig(name: 'S', maxNodes: 4);
      final b = CoordinationSessionConfig(name: 'S', maxNodes: 4);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
    });
  });

  group('defaults', () {
    test('a session ends when its coordinator goes away', () {
      expect(
        CoordinationSessionConfig(name: 'S').coordinatorLossPolicy,
        CoordinatorLossPolicy.endSession,
      );
    });
  });

  group('copyWith', () {
    test('keeps the fields it is not given', () {
      // clockSyncConfig and coordinatorLossPolicy were both dropped here, so any
      // copyWith silently reset a tuned session to the defaults.
      final original = CoordinationSessionConfig(
        name: 'S',
        heartbeatInterval: const Duration(milliseconds: 100),
        nodeTimeout: const Duration(milliseconds: 400),
        coordinatorLossPolicy: CoordinatorLossPolicy.reelect,
        clockSyncConfig: const ClockSyncConfig(
          timeProbeCount: 3,
          timeUpdateMinProbes: 2,
        ),
      );

      final copy = original.copyWith(maxNodes: 7);

      expect(copy.maxNodes, 7);
      expect(copy.coordinatorLossPolicy, CoordinatorLossPolicy.reelect);
      expect(copy.clockSyncConfig.timeProbeCount, 3);
      expect(copy.heartbeatInterval, const Duration(milliseconds: 100));
    });

    test('replaces the fields it is given', () {
      final copy = CoordinationSessionConfig(
        name: 'S',
      ).copyWith(coordinatorLossPolicy: CoordinatorLossPolicy.remainOpen);
      expect(copy.coordinatorLossPolicy, CoordinatorLossPolicy.remainOpen);
    });
  });

  group('serialisation', () {
    test('the policy round-trips through toMap/fromMap', () {
      for (final policy in CoordinatorLossPolicy.values) {
        final config = CoordinationSessionConfig(
          name: 'S',
          coordinatorLossPolicy: policy,
        );
        final decoded = CoordinationSessionConfigFactory().fromMap(
          config.toMap(),
        );
        expect(decoded.coordinatorLossPolicy, policy, reason: policy.name);
      }
    });

    test('an unknown policy name falls back to ending the session', () {
      final decoded = CoordinationSessionConfigFactory().fromMap({
        'name': 'S',
        'coordinatorLossPolicy': 'somethingFromANewerVersion',
      });
      expect(
        decoded.coordinatorLossPolicy,
        CoordinatorLossPolicy.endSession,
        reason: 'the safe default when the wire names something we cannot honour',
      );
    });

    test('fromMap keeps discoveryInterval and the coordinator-consumes flag', () {
      // Both were dropped, so a round trip quietly reset them.
      final original = CoordinationSessionConfig(
        name: 'S',
        discoveryInterval: const Duration(milliseconds: 250),
        consumeCoordinationStreamAsCoordinator: false,
      );
      final decoded = CoordinationSessionConfigFactory().fromMap(
        original.toMap(),
      );
      expect(decoded.discoveryInterval, const Duration(milliseconds: 250));
      expect(decoded.consumeCoordinationStreamAsCoordinator, isFalse);
    });
  });
}
