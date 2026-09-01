/// The scheduling behind an outlet's sample buffers.
///
/// Written from a field failure that this code caused and could not be seen to
/// cause: on 2026-08-31 a participant's coordination stream stopped emitting
/// mid-trial and never resumed, while its data stream kept delivering and the
/// link measured healthy the whole time. The wait for a free buffer was
/// unbounded and held the send lock, so one blocked push in the worker isolate
/// took every subsequent send on that stream with it, forever, silently.
///
/// The properties below are the ones that make that impossible: a wait that
/// ends, a pool that recovers, and a wakeup that always reaches someone who is
/// still listening for it.
library;

import 'dart:async';

import 'package:liblsl_coordinator/transports/lsl/isolate/outlet_buffer_pool.dart';
import 'package:test/test.dart';

void main() {
  OutletBufferPool poolOf({
    int size = 2,
    Duration timeout = const Duration(milliseconds: 50),
  }) => OutletBufferPool(size: size, timeout: timeout);

  test('hands out every buffer before anyone waits', () async {
    final pool = poolOf(size: 3);
    expect(pool.freeCount, 3);
    final indices = [
      await pool.acquire(),
      await pool.acquire(),
      await pool.acquire(),
    ];
    expect(indices.toSet(), hasLength(3), reason: 'no index handed out twice');
    expect(pool.freeCount, 0);
  });

  test('a wait ends rather than lasting forever', () async {
    // The whole point. A worker blocked in a synchronous LSL push never
    // releases, and this used to be the moment the stream died.
    final pool = poolOf(size: 1, timeout: const Duration(milliseconds: 30));
    await pool.acquire();
    await expectLater(pool.acquire(), throwsA(isA<TimeoutException>()));
  });

  test('a timed-out send does not wedge the ones behind it', () async {
    // The consequence that mattered: the failure was permanent, not a dropped
    // sample. Once a buffer comes back the pool must work again.
    final pool = poolOf(size: 1, timeout: const Duration(milliseconds: 30));
    final held = await pool.acquire();
    await expectLater(pool.acquire(), throwsA(isA<TimeoutException>()));

    pool.release(held);
    expect(await pool.acquire(), held);
  });

  test('a release wakes a waiter instead of making it wait out the timeout',
      () async {
    final pool = poolOf(size: 1, timeout: const Duration(seconds: 30));
    final held = await pool.acquire();

    final waiting = pool.acquire();
    // Give the waiter a turn to park before releasing.
    await Future<void>.delayed(Duration.zero);
    pool.release(held);

    expect(await waiting.timeout(const Duration(seconds: 1)), held);
  });

  test('a wakeup is not lost to a waiter that already gave up', () async {
    // A timed-out waiter left in the queue would swallow the next release, and
    // the caller actually waiting would then time out too — a stall that
    // spreads instead of clearing.
    final pool = poolOf(size: 1, timeout: const Duration(milliseconds: 30));
    final held = await pool.acquire();

    await expectLater(pool.acquire(), throwsA(isA<TimeoutException>()));
    expect(pool.waiterCount, 0, reason: 'the abandoned waiter is dropped');

    final waiting = pool.acquire();
    await Future<void>.delayed(Duration.zero);
    pool.release(held);
    expect(await waiting.timeout(const Duration(seconds: 1)), held);
  });

  test('consecutive timeouts are counted, and reset on success', () async {
    // This is the number worth alarming on: one timeout is a slow consumer,
    // several in a row is a stream that has stopped working.
    final pool = poolOf(size: 1, timeout: const Duration(milliseconds: 20));
    final held = await pool.acquire();
    expect(pool.consecutiveTimeouts, 0);

    await expectLater(pool.acquire(), throwsA(isA<TimeoutException>()));
    await expectLater(pool.acquire(), throwsA(isA<TimeoutException>()));
    expect(pool.consecutiveTimeouts, 2);

    pool.release(held);
    await pool.acquire();
    expect(pool.consecutiveTimeouts, 0);
  });

  test('a stopped outlet fails its senders rather than stranding them',
      () async {
    var stopped = false;
    final pool = poolOf(size: 1, timeout: const Duration(seconds: 30));
    await pool.acquire();
    stopped = true;
    await expectLater(
      pool.acquire(isStopped: () => stopped),
      throwsStateError,
    );
  });

  test('failAll releases everyone parked, once', () async {
    // Isolate crash or clean stop: a sender parked here has no other way out.
    final pool = poolOf(size: 1, timeout: const Duration(seconds: 30));
    await pool.acquire();

    final first = pool.acquire();
    await Future<void>.delayed(Duration.zero);
    pool.failAll(StateError('isolate exited'));

    await expectLater(first, throwsStateError);
    expect(pool.waiterCount, 0);
    // A second failAll must not throw on the already-completed waiter.
    pool.failAll(StateError('again'));
  });

  test('a release racing a timeout is not a dropped sample', () async {
    // The pool re-checks free buffers before giving up, so a buffer that came
    // back in the same turn is used rather than wasted.
    final pool = poolOf(size: 1, timeout: const Duration(milliseconds: 40));
    final held = await pool.acquire();

    Timer(const Duration(milliseconds: 39), () => pool.release(held));
    // Either outcome is correct; what must not happen is a throw when a buffer
    // is sitting free.
    try {
      final index = await pool.acquire();
      expect(index, held);
    } on TimeoutException {
      expect(pool.freeCount, 1, reason: 'the buffer is back for the next call');
    }
  });
}
