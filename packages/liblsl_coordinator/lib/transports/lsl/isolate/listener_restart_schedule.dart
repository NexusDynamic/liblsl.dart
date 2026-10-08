/// Decides how long a dead sample listener waits before it is restarted, and
/// when restarting it is no longer enough and its inlet should be reopened.
///
/// Separated from the inlet worker for the same reason as
/// `TimeCorrectionSchedule`: the behaviour is pure bookkeeping, and the
/// failures it answers cannot be produced on demand.
///
/// A listener is an isolate waiting inside `lsl_pull_sample` for one inlet.
/// When it ends without being asked to, starting another on the same inlet is
/// cheap and usually enough, so that is tried first and at once. One that
/// keeps dying is restarted with exponential backoff, so a listener that
/// cannot run costs an isolate spawn every few seconds rather than a loop of
/// them. As with time corrections, the cap is on patience, not a give-up: it
/// is retried for as long as its inlet exists.
///
/// Keyed by source id, as `TimeCorrectionSchedule` is: a reopened inlet is a
/// new object for the same peer, and the count has to survive that.
class ListenerRestartSchedule {
  ListenerRestartSchedule({
    this.initialDelay = const Duration(milliseconds: 100),
    this.maxDelay = const Duration(seconds: 5),
    this.reopenAfter = 3,
  }) : assert(initialDelay > Duration.zero, 'A restart needs some delay'),
       assert(maxDelay >= initialDelay, 'The cap cannot be below the start'),
       assert(reopenAfter > 0, 'Reopening needs at least one failure');

  /// liblsl's `lsl_lost_error`: the stream is gone and the inlet will not
  /// recover it.
  static const int lostErrorCode = -2;

  /// Delay before the first restart; doubled for every further failure.
  final Duration initialDelay;

  /// Upper bound on the delay.
  final Duration maxDelay;

  /// Consecutive failures from which the inlet is reopened instead of only
  /// listened to again.
  final int reopenAfter;

  final Map<String, int> _failures = {};

  /// Consecutive failures recorded for [sourceId]; zero when healthy.
  int failuresFor(String sourceId) => _failures[sourceId] ?? 0;

  /// Records a listener that ended by itself and returns how long to wait
  /// before the next attempt.
  Duration noteFailure(String sourceId) {
    final failures = (_failures[sourceId] ?? 0) + 1;
    _failures[sourceId] = failures;
    // Clamp the shift itself, as TimeCorrectionSchedule does: 1 << 63 is
    // negative, and a listener that has been dying for a long time must not
    // come back to being restarted with no delay.
    final doublings = failures - 1;
    if (doublings >= 31) return maxDelay;
    final delay = initialDelay * (1 << doublings);
    return delay > maxDelay ? maxDelay : delay;
  }

  /// Whether the next attempt for [sourceId] should reopen its inlet.
  ///
  /// [errorCode] is the liblsl code the listener ended with, if it ended on
  /// one. A lost stream is reopened at once; anything else only when
  /// restarting the listener has already failed [reopenAfter] times running.
  bool shouldReopenInlet(String sourceId, {int? errorCode}) =>
      errorCode == lostErrorCode || failuresFor(sourceId) >= reopenAfter;

  /// Records that the listener for [sourceId] is working, returning true if
  /// that ended a run of failures (a recovery worth reporting).
  bool noteHealthy(String sourceId) => _failures.remove(sourceId) != null;

  /// Drops all bookkeeping for an inlet that is going away.
  void forget(String sourceId) => _failures.remove(sourceId);
}
