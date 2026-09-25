import 'dart:async';
import 'dart:collection';

/// Index bookkeeping for an outlet's pool of reusable native sample buffers.
///
/// Separated from the isolate that owns the buffers themselves because the
/// interesting behaviour here is pure scheduling — who waits, for how long, and
/// what happens when nothing ever comes back — and that behaviour was the cause
/// of a permanent, silent failure that could not be reproduced without a
/// network fault.
///
/// The failure: the worker isolate pushes samples with a *blocking* LSL call,
/// and LSL's push blocks when a consumer stops draining. A blocked worker never
/// returns its buffer, so the pool empties, and the acquire that follows used to
/// wait forever — while holding the send lock. Every later send on that stream
/// queued behind it and never ran again, permanently, while every other stream
/// in the same process carried on normally. On 2026-08-31 that is exactly what
/// a participant looked like: coordination heartbeats stopped dead mid-trial
/// and never resumed, its data stream kept delivering, the link measured
/// healthy the whole time, and the coordinator evicted it ten seconds later.
///
/// So: a bounded wait. Dropping a sample is recoverable. Wedging a stream is
/// not.
class OutletBufferPool {
  OutletBufferPool({required this.size, required this.timeout})
    : assert(size > 0, 'A pool needs at least one buffer') {
    for (var i = 0; i < size; i++) {
      _free.add(i);
    }
  }

  /// Number of buffers in the pool.
  final int size;

  /// How long [acquire] waits before giving up. Mutable so a caller can tune it
  /// to the stream's cadence.
  ///
  /// The default does not need to scale with sample rate, which is what makes a
  /// flat value defensible here: the pool being empty for this long means the
  /// worker has not completed a *single* push in that time, and a push that
  /// takes seconds is a wedge at 10 Hz exactly as much as at 120 Hz. A stream
  /// that is merely slow cycles buffers continuously and never comes near it.
  Duration timeout;

  final ListQueue<int> _free = ListQueue<int>();
  final ListQueue<Completer<void>> _waiters = ListQueue<Completer<void>>();

  /// Buffers currently available.
  int get freeCount => _free.length;

  /// Callers currently parked waiting for one.
  int get waiterCount => _waiters.length;

  /// Consecutive [acquire] calls that timed out. Reset by the next success.
  ///
  /// The number worth logging and alarming on: one timeout is a slow consumer,
  /// several in a row is a stream that has stopped working.
  int get consecutiveTimeouts => _consecutiveTimeouts;
  int _consecutiveTimeouts = 0;

  /// Takes a free buffer index, waiting up to [timeout] for one.
  ///
  /// Throws [TimeoutException] rather than waiting indefinitely. If
  /// [isStopped] starts returning true while parked, throws [StateError]
  /// instead — a stopped stream should fail its senders, not strand them.
  Future<int> acquire({bool Function()? isStopped}) async {
    while (_free.isEmpty) {
      if (isStopped?.call() ?? false) {
        throw StateError('Cannot acquire a buffer: the outlet is stopped');
      }
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await waiter.future.timeout(timeout);
      } on TimeoutException {
        // Drop it from the queue on the way out. Left in place, the next
        // release would hand its wakeup to a waiter nobody is listening to,
        // and the caller that *is* waiting would miss it.
        _waiters.remove(waiter);
        // A release can land in the same turn the timeout fires. Having
        // already paid the wait, take the buffer rather than dropping a
        // sample over a race.
        if (_free.isNotEmpty) continue;
        _consecutiveTimeouts++;
        rethrow;
      }
    }
    _consecutiveTimeouts = 0;
    return _free.removeFirst();
  }

  /// Returns a buffer to the pool and wakes one waiter.
  void release(int index) {
    _free.add(index);
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      // Skip any a timeout already abandoned, so the wakeup reaches someone
      // still listening for it.
      if (!waiter.isCompleted) {
        waiter.complete();
        return;
      }
    }
  }

  /// Fails everyone parked on the pool, for a clean stop or an isolate crash.
  void failAll(Object error) {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }
}
