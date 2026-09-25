/// The clock-offset arithmetic, pinned with injected timestamps.
///
/// No sockets, no timers, no sleeping. Every test here builds the four NTP
/// timestamps by hand from a *known* true offset and a *known* path delay, then
/// checks that the estimator recovers what it should — including the cases
/// where it deliberately should not (an under-filled burst, a stale wave).
///
/// The reference is liblsl's `time_receiver.cpp`; where behaviour is
/// surprising, the surprise is liblsl's and is reproduced on purpose.
library;

import 'package:peer_coordinator/coordination.dart';
import 'package:test/test.dart';

/// Builds one probe exchange from a ground truth.
///
/// [trueOffset] is how far ahead the peer's clock reads (`remote - local`).
/// [outbound]/[inbound] are the one-way delays of the two legs, so an
/// asymmetric path can be expressed directly.
ClockProbeSample probe({
  required double t0,
  required double trueOffset,
  required double outbound,
  required double inbound,
  double remoteDwell = 0.0,
}) {
  final t1 = t0 + outbound + trueOffset;
  final t2 = t1 + remoteDwell;
  final t3 = t2 - trueOffset + inbound;
  return ClockProbeSample(t0: t0, t1: t1, t2: t2, t3: t3);
}

void main() {
  group('ClockProbeSample', () {
    test('recovers a symmetric offset exactly', () {
      // Peer's clock reads 10s ahead of ours; 5ms each way.
      final sample = probe(
        t0: 100.0,
        trueOffset: 10.0,
        outbound: 0.005,
        inbound: 0.005,
      );

      expect(sample.rawOffset, closeTo(10.0, 1e-9));
      expect(sample.rtt, closeTo(0.010, 1e-9));
    });

    test('a slow responder distorts neither the rtt nor the offset', () {
      final sample = probe(
        t0: 0.0,
        trueOffset: 3.0,
        outbound: 0.002,
        inbound: 0.002,
        // The responder sat on it for a full second. That is not network time,
        // and it is why the exchange carries t1 and t2 separately rather than a
        // single "the peer's clock" reading.
        remoteDwell: 1.0,
      );

      // `(t3-t0) - (t2-t1)` subtracts the dwell back out.
      expect(sample.rtt, closeTo(0.004, 1e-9));
      // And it cancels from the offset too: the +1s in (t1-t0) is matched by a
      // -1s in (t2-t3), so a slow responder costs accuracy nothing.
      expect(sample.rawOffset, closeTo(3.0, 1e-9));
    });

    test('an asymmetric path biases the offset by half the asymmetry', () {
      // 9ms out, 1ms back: 8ms of asymmetry, so a 4ms bias. This is inherent to
      // NTP's two-timestamp method, not a defect — pinned so nobody "fixes" it.
      final sample = probe(
        t0: 0.0,
        trueOffset: 2.0,
        outbound: 0.009,
        inbound: 0.001,
      );

      expect(sample.rtt, closeTo(0.010, 1e-9));
      expect(sample.rawOffset, closeTo(2.004, 1e-9));
    });

    test('remoteTime is the midpoint of the peer-side dwell', () {
      final sample = probe(
        t0: 0.0,
        trueOffset: 0.0,
        outbound: 0.001,
        inbound: 0.001,
        remoteDwell: 0.010,
      );
      expect(sample.remoteTime, closeTo(0.006, 1e-9));
    });
  });

  group('PeerClockEstimator', () {
    const config = ClockSyncConfig(timeProbeCount: 8, timeUpdateMinProbes: 6);

    PeerClockEstimator makeEstimator() =>
        PeerClockEstimator(peerUId: 'peer-1', config: config);

    test('publishes nothing before a burst is accepted', () {
      expect(makeEstimator().estimate, isNull);
    });

    test(
      'negates the raw offset so it maps a remote stamp into local time',
      () {
        final estimator = makeEstimator();
        final wave = estimator.beginBurst();
        for (var i = 0; i < 6; i++) {
          estimator.addSample(
            wave,
            probe(
              t0: i.toDouble(),
              trueOffset: 10.0,
              outbound: 0.005,
              inbound: 0.005,
            ),
          );
        }

        final estimate = estimator.aggregate()!;
        // The peer reads 10s ahead, so -10s is what maps its stamps to ours.
        expect(estimate.offset, closeTo(-10.0, 1e-9));

        // And that is exactly what makes the arithmetic work out:
        const remoteStamp = 110.0;
        expect(remoteStamp + estimate.offset, closeTo(100.0, 1e-9));
      },
    );

    test('takes the lowest-RTT probe, not the average or the last', () {
      final estimator = makeEstimator();
      final wave = estimator.beginBurst();

      // Five badly-queued probes, asymmetric enough to be visibly wrong...
      for (var i = 0; i < 5; i++) {
        estimator.addSample(
          wave,
          probe(
            t0: i.toDouble(),
            trueOffset: 4.0,
            outbound: 0.100,
            inbound: 0.002,
          ),
        );
      }
      // ...and one clean one, which should win despite arriving last.
      estimator.addSample(
        wave,
        probe(t0: 5.0, trueOffset: 4.0, outbound: 0.001, inbound: 0.001),
      );

      final estimate = estimator.aggregate()!;
      expect(estimate.offset, closeTo(-4.0, 1e-6));
      expect(estimate.uncertainty, closeTo(0.002, 1e-9));
      // The queued probes each carry a 49ms bias (half of 98ms asymmetry).
      // Averaging the six would land ~41ms out; argmin-RTT lands within a
      // microsecond, which is the whole reason liblsl picks the minimum.
      expect((estimate.offset + 4.0).abs(), lessThan(0.001));
    });

    test('uncertainty is the full RTT, not half of it', () {
      final estimator = makeEstimator();
      final wave = estimator.beginBurst();
      for (var i = 0; i < 6; i++) {
        estimator.addSample(
          wave,
          probe(
            t0: i.toDouble(),
            trueOffset: 0.0,
            outbound: 0.004,
            inbound: 0.004,
          ),
        );
      }
      final estimate = estimator.aggregate()!;
      // liblsl reports the whole round trip as the error bound.
      expect(estimate.uncertainty, closeTo(0.008, 1e-9));
    });

    test('discards a burst that did not reach the minimum probe count', () {
      final estimator = makeEstimator();

      // A good burst establishes a baseline.
      final firstWave = estimator.beginBurst();
      for (var i = 0; i < 6; i++) {
        estimator.addSample(
          firstWave,
          probe(
            t0: i.toDouble(),
            trueOffset: 1.0,
            outbound: 0.001,
            inbound: 0.001,
          ),
        );
      }
      expect(estimator.aggregate(), isNotNull);
      final baseline = estimator.estimate!;

      // The next burst loses most of its replies. It must not publish, and must
      // not clobber the previous estimate with a worse one.
      final secondWave = estimator.beginBurst();
      for (var i = 0; i < 5; i++) {
        estimator.addSample(
          secondWave,
          probe(
            t0: i.toDouble(),
            trueOffset: 99.0,
            outbound: 0.001,
            inbound: 0.001,
          ),
        );
      }
      expect(estimator.aggregate(), isNull);
      expect(estimator.estimate, same(baseline));
    });

    test('drops replies quoting a superseded wave', () {
      final estimator = makeEstimator();
      final staleWave = estimator.beginBurst();
      final currentWave = estimator.beginBurst();
      expect(currentWave, isNot(staleWave));

      final accepted = estimator.addSample(
        currentWave,
        probe(t0: 0, trueOffset: 1.0, outbound: 0.001, inbound: 0.001),
      );
      final rejected = estimator.addSample(
        staleWave,
        probe(t0: 0, trueOffset: 1.0, outbound: 0.001, inbound: 0.001),
      );

      expect(accepted, isTrue);
      expect(rejected, isFalse);
      expect(estimator.repliesThisBurst, 1);
    });

    test('beginBurst clears the previous burst, so nothing carries over', () {
      final estimator = makeEstimator();
      final first = estimator.beginBurst();
      for (var i = 0; i < 8; i++) {
        estimator.addSample(
          first,
          probe(
            t0: i.toDouble(),
            trueOffset: 1,
            outbound: 0.001,
            inbound: 0.001,
          ),
        );
      }
      expect(estimator.repliesThisBurst, 8);

      estimator.beginBurst();
      expect(estimator.repliesThisBurst, 0);
    });

    test('reset forgets the estimate, reporting unknown rather than stale', () {
      final estimator = makeEstimator();
      final wave = estimator.beginBurst();
      for (var i = 0; i < 6; i++) {
        estimator.addSample(
          wave,
          probe(
            t0: i.toDouble(),
            trueOffset: 1.0,
            outbound: 0.001,
            inbound: 0.001,
          ),
        );
      }
      expect(estimator.aggregate(), isNotNull);

      estimator.reset();
      expect(estimator.estimate, isNull);
    });
  });

  group('ClockSyncConfig', () {
    test('defaults mirror liblsl tuning', () {
      const config = ClockSyncConfig();
      expect(config.timeUpdateInterval, const Duration(seconds: 2));
      expect(config.timeProbeCount, 8);
      expect(config.timeProbeInterval, const Duration(milliseconds: 64));
      expect(config.timeProbeMaxRtt, const Duration(milliseconds: 128));
      expect(config.timeUpdateMinProbes, 6);
      // TimeProbeMaxRTT + TimeProbeInterval * TimeProbeCount = 640ms
      expect(config.aggregateAfter, const Duration(milliseconds: 640));
    });

    test('rejects a minimum that no burst could ever reach', () {
      expect(
        () => const ClockSyncConfig(
          timeProbeCount: 4,
          timeUpdateMinProbes: 5,
        ).validate(throwOnError: true),
        throwsArgumentError,
      );
    });

    test('rejects an interval shorter than a burst takes to aggregate', () {
      expect(
        () => const ClockSyncConfig(
          timeUpdateInterval: Duration(milliseconds: 100),
        ).validate(throwOnError: true),
        throwsArgumentError,
      );
    });
  });

  group('PeerClockOffsets', () {
    test('reports null for peers it has never heard of', () {
      final offsets = PeerClockOffsets();
      expect(offsets.offsetFor('nobody'), isNull);
      expect(offsets.uncertaintyFor('nobody'), isNull);
      expect(offsets.offsetFor(null), isNull);
    });

    test('stores and forgets per peer', () {
      final offsets = PeerClockOffsets();
      offsets.set(
        'peer-1',
        const ClockOffsetEstimate(
          offset: -1.5,
          uncertainty: 0.004,
          remoteTime: 10.0,
          sampledAt: 5.0,
        ),
      );

      expect(offsets.offsetFor('peer-1'), -1.5);
      expect(offsets.uncertaintyFor('peer-1'), 0.004);
      expect(offsets.peers, contains('peer-1'));

      offsets.remove('peer-1');
      expect(offsets.offsetFor('peer-1'), isNull);
    });
  });
}
