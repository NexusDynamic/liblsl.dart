/// Decides which inlets a time-correction sweep touches, and when it stops.
///
/// Separated from the inlet worker for the same reason as `OutletBufferPool`:
/// the interesting behaviour is pure scheduling — who gets skipped, for how
/// long, and when a sweep gives up — and that behaviour caused a failure that
/// could not be reproduced without a network fault.
///
/// The failure: an inlet worker owns *every* inlet on its stream, in one
/// isolate, and refreshes their clock offsets on a timer. Those inlets are
/// built with `useIsolates: false`, so `lsl_time_correction_ex` runs as a
/// synchronous FFI call on the worker's own thread — `Future.wait` over them is
/// bookkeeping, not concurrency. One unreachable peer therefore cost its full
/// timeout out of every sweep, forever, and while the worker was inside that
/// call it polled *no* inlet at all.
///
/// On 2026-09-02 a coordinator re-created an inlet for a participant whose
/// Wi-Fi had dropped into a ~34 s black hole. It then stopped reading
/// heartbeats from the five healthy participants, decided all five had gone
/// silent, and evicted the entire session — while a second inlet worker, on a
/// different stream in the same process, ran normally throughout.
///
/// So: two bounds, because they fail differently. [noteFailure] backs a dead
/// peer off exponentially, which handles the steady state. [Sweep.isExhausted]
/// caps one sweep's total cost, which handles the burst — six peers dropping at
/// once would otherwise cost six timeouts back to back before any backoff had
/// been recorded.
///
/// Keyed by source id rather than by index because inlet indices shift under
/// removal, and this worker already carries two index-parallel lists that must
/// be kept in lockstep.
class TimeCorrectionSchedule {
  TimeCorrectionSchedule({required this.maxSkips, required this.sweepBudget})
    : assert(maxSkips > 0, 'Backoff has to allow at least one skip'),
      assert(sweepBudget > Duration.zero, 'A sweep needs a budget to spend');

  /// Upper bound on the exponential backoff, in sweeps.
  ///
  /// Caps how long a peer that has never answered goes unretried. It is a cap
  /// on patience, not a give-up: the inlet is retried forever, just rarely.
  final int maxSkips;

  /// Wall-clock budget for one pass over all inlets.
  final Duration sweepBudget;

  final Map<String, int> _failures = {};
  final Map<String, int> _skips = {};

  /// Consecutive failures recorded for [sourceId]; zero when healthy.
  int failuresFor(String sourceId) => _failures[sourceId] ?? 0;

  /// Sweeps [sourceId] will still be skipped before it is retried.
  int skipsFor(String sourceId) => _skips[sourceId] ?? 0;

  /// Source ids currently in backoff.
  Iterable<String> get backingOff => _skips.keys;

  /// Whether this sweep should skip [sourceId], consuming one of its skips.
  ///
  /// Consuming on the *query* is what makes the backoff advance without the
  /// caller having to remember to tick it, and means a skipped inlet costs one
  /// map lookup rather than a timeout.
  bool shouldSkip(String sourceId) {
    final skips = _skips[sourceId] ?? 0;
    if (skips <= 0) return false;
    _skips[sourceId] = skips - 1;
    return true;
  }

  /// Records a failed refresh and returns how many sweeps it will now be
  /// skipped for.
  ///
  /// Doubling per failure: 1, 2, 4, 8 … capped at [maxSkips]. A peer that comes
  /// back is picked up on the next retry, and one that does not costs
  /// asymptotically nothing.
  int noteFailure(String sourceId) {
    final failures = (_failures[sourceId] ?? 0) + 1;
    _failures[sourceId] = failures;
    // Shift rather than pow, and clamp the shift itself: 1 << 63 is negative
    // and 1 << 64 is zero on a 64-bit int, so a long-dead peer would silently
    // come back to being retried every sweep.
    final doublings = failures - 1;
    final backoff = doublings >= 31 ? maxSkips : _min(1 << doublings, maxSkips);
    _skips[sourceId] = backoff;
    return backoff;
  }

  /// Records a successful refresh, returning true if it ended a run of
  /// failures (i.e. this is a recovery worth logging).
  bool noteSuccess(String sourceId) {
    final recovered = _failures.remove(sourceId) != null;
    _skips.remove(sourceId);
    return recovered;
  }

  /// Drops all bookkeeping for an inlet that is going away.
  void forget(String sourceId) {
    _failures.remove(sourceId);
    _skips.remove(sourceId);
  }

  /// Begins a sweep. Call [Sweep.isExhausted] after each refresh.
  Sweep beginSweep() => Sweep._(sweepBudget);

  static int _min(int a, int b) => a < b ? a : b;
}

/// One pass over the inlets, and the budget it is spending.
class Sweep {
  Sweep._(this._budget) : _clock = Stopwatch()..start();

  final Duration _budget;
  final Stopwatch _clock;

  /// Time spent so far in this sweep.
  Duration get elapsed => _clock.elapsed;

  /// Whether the budget is spent and the remaining inlets should be deferred.
  ///
  /// Meant to be checked *after* refreshing an inlet, not before, so that every
  /// sweep makes at least one inlet's worth of progress. Checking first would
  /// let a budget that is already spent on entry starve the first inlet in the
  /// list forever.
  bool get isExhausted => _clock.elapsed > _budget;
}
