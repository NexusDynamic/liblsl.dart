import 'package:peer_coordinator/src/coordination/pending_joins.dart';
import 'package:test/test.dart';

/// Regression cover for the join slot that was never released.
///
/// A coordinator marks a node as "joining" before creating its inlet and
/// sending a join offer, and used to unmark it only on a successful join, an
/// explicit rejection, or the inlet creation throwing. A join offer has no ack
/// and no retry, so a lost offer meant none of those three ever happened. The
/// node's id stayed marked for the lifetime of the process and every later
/// discovery cycle logged `Join already in progress ... skipping` — forever.
///
/// It could not heal on its own, because a rejoining node keeps its node id:
/// the id it presents is the one already stuck. That cost one participant the
/// rest of the session on 2026-08-31, and all six on 2026-09-02.
///
/// Time is injected rather than slept through: these are deadline semantics,
/// and a test that waits out a real TTL is both slow and flaky.
void main() {
  final t0 = DateTime.utc(2026, 9, 2, 10, 43);
  PendingJoins joins({Duration ttl = const Duration(seconds: 20)}) =>
      PendingJoins(ttl: ttl);

  test('a node with no join in flight is not in progress', () {
    expect(joins().isInProgress('nobody', now: t0), isFalse);
  });

  test('a started join is in progress', () {
    final j = joins()..start('parsnip', now: t0);
    expect(j.isInProgress('parsnip', now: t0), isTrue);
    expect(j.inFlight, contains('parsnip'));
    expect(j.length, 1);
  });

  test('a completed join releases its slot immediately', () {
    final j = joins()..start('parsnip', now: t0);
    j.complete('parsnip');
    expect(j.isInProgress('parsnip', now: t0), isFalse);
    expect(j.length, 0);
  });

  test('a join still within its deadline keeps blocking re-offers', () {
    // The guard has to keep doing its original job: without it, every discovery
    // cycle would fire a duplicate addInlet and join offer at a node that is
    // simply mid-handshake.
    final j = joins(ttl: const Duration(seconds: 20))..start('slow', now: t0);
    expect(
      j.isInProgress('slow', now: t0.add(const Duration(seconds: 19))),
      isTrue,
    );
  });

  test('a join past its deadline releases the slot', () {
    final j = joins(ttl: const Duration(seconds: 20))..start('lost', now: t0);
    expect(
      j.isInProgress('lost', now: t0.add(const Duration(seconds: 21))),
      isFalse,
      reason: 'a handshake that never completed must not lock the node out',
    );
  });

  test('the deadline is inclusive, so exactly-at-TTL releases', () {
    final j = joins(ttl: const Duration(seconds: 20))..start('edge', now: t0);
    expect(
      j.isInProgress('edge', now: t0.add(const Duration(seconds: 20))),
      isFalse,
    );
  });

  test('expiry is permanent, not a one-off skip', () {
    // Lazy expiry drops the entry as a side effect of the query. If it did not,
    // the very next cycle would see the stale entry again and the node would
    // still be locked out.
    final j = joins(ttl: const Duration(seconds: 20))..start('lost', now: t0);
    final later = t0.add(const Duration(seconds: 21));
    expect(j.isInProgress('lost', now: later), isFalse);
    expect(j.length, 0, reason: 'the entry is gone, not merely ignored');
    expect(j.isInProgress('lost', now: later), isFalse);
  });

  test('a re-offered node starts a fresh deadline', () {
    final j = joins(ttl: const Duration(seconds: 20))..start('retry', now: t0);
    final expired = t0.add(const Duration(seconds: 21));
    expect(j.isInProgress('retry', now: expired), isFalse);

    j.start('retry', now: expired);
    expect(
      j.isInProgress('retry', now: expired.add(const Duration(seconds: 5))),
      isTrue,
      reason: 'the retry gets its own full window, not the remains of the last',
    );
  });

  test('deadlines are per node', () {
    final j = joins(ttl: const Duration(seconds: 20))
      ..start('early', now: t0)
      ..start('late', now: t0.add(const Duration(seconds: 15)));
    final at = t0.add(const Duration(seconds: 21));
    expect(j.isInProgress('early', now: at), isFalse);
    expect(j.isInProgress('late', now: at), isTrue);
  });

  test('in-flight duration is reported, for a log that shows the wait', () {
    final j = joins()..start('parsnip', now: t0);
    expect(
      j.inFlightFor('parsnip', now: t0.add(const Duration(seconds: 7))),
      const Duration(seconds: 7),
    );
    expect(j.inFlightFor('nobody', now: t0), isNull);
  });

  test('clear releases every slot, for a role or session teardown', () {
    final j = joins()
      ..start('a', now: t0)
      ..start('b', now: t0);
    j.clear();
    expect(j.length, 0);
    expect(j.isInProgress('a', now: t0), isFalse);
  });

  test('length and inFlight do not expire entries', () {
    // Diagnostics must not mutate the thing they are reporting on.
    final j = joins(ttl: const Duration(seconds: 20))..start('lost', now: t0);
    expect(j.length, 1);
    expect(j.inFlight, contains('lost'));
    expect(j.length, 1);
  });

  test(
    'a zero or negative TTL is rejected rather than locking out forever',
    () {
      expect(
        () => PendingJoins(ttl: Duration.zero),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PendingJoins(ttl: const Duration(seconds: -1)),
        throwsA(isA<AssertionError>()),
      );
    },
  );
}
