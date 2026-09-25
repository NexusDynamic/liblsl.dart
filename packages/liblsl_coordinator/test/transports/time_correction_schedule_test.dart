import 'package:liblsl_coordinator/transports/lsl/isolate/time_correction_schedule.dart';
import 'package:test/test.dart';

/// Regression cover for the 2026-09-02 session-wide eviction cascade.
///
/// One participant's Wi-Fi dropped into a ~34 s black hole. The coordinator's
/// inlet worker — which owns every peer's coordination inlet in a single
/// isolate — then blocked inside synchronous FFI calls against that peer and
/// polled nobody at all. Five healthy participants went unread, were judged
/// silent, and the whole session was evicted.
///
/// These tests pin the two bounds that stop one unreachable peer from costing
/// every other peer their delivery. They are deliberately network-free: the
/// original fault could not be reproduced without one, which is exactly why the
/// policy lives in its own object.
void main() {
  TimeCorrectionSchedule schedule({
    int maxSkips = 32,
    Duration sweepBudget = const Duration(milliseconds: 1500),
  }) => TimeCorrectionSchedule(maxSkips: maxSkips, sweepBudget: sweepBudget);

  group('backoff', () {
    test('a healthy inlet is never skipped', () {
      final s = schedule();
      for (var i = 0; i < 10; i++) {
        expect(s.shouldSkip('healthy'), isFalse);
      }
      expect(s.failuresFor('healthy'), 0);
    });

    test(
      'failures double the skip count, so a dead peer costs less each time',
      () {
        final s = schedule();
        expect(s.noteFailure('dead'), 1);
        expect(s.noteFailure('dead'), 2);
        expect(s.noteFailure('dead'), 4);
        expect(s.noteFailure('dead'), 8);
        expect(s.failuresFor('dead'), 4);
      },
    );

    test('backoff is capped, so a peer is retried forever, just rarely', () {
      final s = schedule(maxSkips: 8);
      for (var i = 0; i < 40; i++) {
        expect(s.noteFailure('dead'), lessThanOrEqualTo(8));
      }
      expect(s.skipsFor('dead'), 8);
    });

    test('a very long outage does not wrap the shift back to zero', () {
      // 1 << 63 is negative and 1 << 64 is zero on a 64-bit int. Either would
      // silently return a long-dead peer to being retried on every sweep —
      // reinstating the per-sweep cost this class exists to remove.
      final s = schedule(maxSkips: 32);
      for (var i = 0; i < 200; i++) {
        expect(s.noteFailure('ancient'), greaterThan(0));
      }
      expect(s.skipsFor('ancient'), 32);
    });

    test(
      'skips are consumed one sweep at a time, then the inlet is retried',
      () {
        final s = schedule();
        s.noteFailure('flaky'); // 1 skip
        s.noteFailure('flaky'); // 2 skips
        expect(s.shouldSkip('flaky'), isTrue);
        expect(s.shouldSkip('flaky'), isTrue);
        expect(
          s.shouldSkip('flaky'),
          isFalse,
          reason: 'the backoff has to expire, or the peer is abandoned',
        );
      },
    );

    test('recovery clears the backoff and is reported once', () {
      final s = schedule();
      s.noteFailure('back');
      expect(s.noteSuccess('back'), isTrue, reason: 'ended a run of failures');
      expect(s.failuresFor('back'), 0);
      expect(s.skipsFor('back'), 0);
      expect(
        s.noteSuccess('back'),
        isFalse,
        reason: 'a healthy inlet must not log a recovery on every sweep',
      );
    });

    test('backoff is per inlet, so one dead peer does not skip the others', () {
      final s = schedule();
      s.noteFailure('dead');
      expect(s.shouldSkip('dead'), isTrue);
      expect(s.shouldSkip('healthy'), isFalse);
      expect(s.backingOff, contains('dead'));
      expect(s.backingOff, isNot(contains('healthy')));
    });

    test('a removed inlet leaves no bookkeeping behind', () {
      final s = schedule();
      s.noteFailure('gone');
      s.forget('gone');
      expect(s.failuresFor('gone'), 0);
      expect(s.skipsFor('gone'), 0);
      expect(s.backingOff, isEmpty);
      expect(
        s.shouldSkip('gone'),
        isFalse,
        reason: 'a peer that rejoins under the same id starts clean',
      );
    });
  });

  group('sweep budget', () {
    test('a fresh sweep has budget to spend', () {
      expect(schedule().beginSweep().isExhausted, isFalse);
    });

    test('a sweep that overruns its budget reports exhausted', () async {
      final sweep = schedule(
        sweepBudget: const Duration(milliseconds: 20),
      ).beginSweep();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(sweep.isExhausted, isTrue);
      expect(sweep.elapsed, greaterThan(const Duration(milliseconds: 20)));
    });

    test('the budget bounds a burst, which backoff alone cannot', () async {
      // The burst case: six peers drop simultaneously, so none of them has a
      // failure recorded yet and none is in backoff. Without a budget the sweep
      // pays every one of their timeouts back to back — which is precisely the
      // window in which the coordinator stopped polling and evicted everyone.
      final s = schedule(sweepBudget: const Duration(milliseconds: 30));
      final sweep = s.beginSweep();
      var refreshed = 0;
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        refreshed++;
        if (sweep.isExhausted) break;
      }
      expect(
        refreshed,
        lessThan(6),
        reason: 'the sweep must give up rather than pay every peer in full',
      );
      expect(
        refreshed,
        greaterThan(0),
        reason: 'checked after the refresh, so a sweep always makes progress',
      );
    });

    test('each sweep gets a fresh budget', () async {
      final s = schedule(sweepBudget: const Duration(milliseconds: 20));
      final first = s.beginSweep();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(first.isExhausted, isTrue);
      expect(
        s.beginSweep().isExhausted,
        isFalse,
        reason: 'an exhausted sweep must not poison the next one',
      );
    });
  });

  group('construction', () {
    test('rejects a schedule that could never retry or never progress', () {
      expect(
        () => TimeCorrectionSchedule(
          maxSkips: 0,
          sweepBudget: const Duration(seconds: 1),
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => TimeCorrectionSchedule(maxSkips: 8, sweepBudget: Duration.zero),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
