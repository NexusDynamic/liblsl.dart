/// The outlet worker's promise that a pooled buffer always comes back.
///
/// `_handleData` cannot be exercised without an isolate and a live LSL outlet,
/// so what is pinned here is the shape of its contract against the pool it
/// feeds: a release must happen on every path, including the one where the push
/// throws. Before this, the release sat after the push with no `finally`, so a
/// single throw leaked a buffer — and eight leaks killed that stream's outbound
/// traffic permanently and silently, which is the failure mode the whole
/// [OutletBufferPool] timeout exists to bound.
library;

import 'dart:async';

import 'package:liblsl_coordinator/transports/lsl/isolate/outlet_buffer_pool.dart';
import 'package:test/test.dart';

void main() {
  /// Stands in for the worker: pushes, then releases, the way `_handleData`
  /// does — with [shouldThrow] deciding whether the push fails.
  Future<void> handleOne(
    OutletBufferPool pool,
    int index, {
    required bool shouldThrow,
  }) async {
    try {
      if (shouldThrow) throw StateError('Outlet not initialized');
    } catch (_) {
      // Swallowed, exactly as the worker does: rethrowing would surface as an
      // uncaught async error and, with errorsAreFatal, take the isolate down.
    } finally {
      pool.release(index);
    }
  }

  test('a failing push still returns its buffer', () async {
    final pool = OutletBufferPool(
      size: 2,
      timeout: const Duration(milliseconds: 50),
    );

    // Every push throws, which is what a destroyed outlet does.
    for (var i = 0; i < 20; i++) {
      final index = await pool.acquire();
      await handleOne(pool, index, shouldThrow: true);
    }

    expect(
      pool.freeCount,
      2,
      reason: 'a pool that leaks on the throw path empties and never refills',
    );
    expect(pool.consecutiveTimeouts, 0);
  });

  test('without the release, the pool dies after exactly poolSize sends',
      () async {
    // Characterises the old behaviour, so a regression is unmistakable rather
    // than showing up months later as a frozen iPad.
    final pool = OutletBufferPool(
      size: 3,
      timeout: const Duration(milliseconds: 20),
    );

    for (var i = 0; i < 3; i++) {
      await pool.acquire(); // acquired and never released
    }

    await expectLater(pool.acquire(), throwsA(isA<TimeoutException>()));
  });
}
